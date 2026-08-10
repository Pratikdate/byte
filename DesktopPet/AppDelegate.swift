import AppKit
import SwiftUI
import SceneKit
import SpriteKit // For the 2D screen material
import UserNotifications

class PetWindow: NSWindow {
    var acceptsKey: Bool = false
    override var canBecomeKey: Bool { return acceptsKey }
    override var canBecomeMain: Bool { return acceptsKey }
}

class PetSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept clicks if they actually hit the 3D pet model
        let localPoint = convert(point, from: superview)
        let hits = self.hitTest(localPoint, options: [:])
        
        // Ignore hits on the invisible SCNFloor (which is infinitely large)
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        
        if validHits.isEmpty {
            return nil // Click passes perfectly through to the desktop
        }
        
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        (scene as? PetScene)?.handleMouseDown(at: location, viewSize: bounds.size)
    }
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        (scene as? PetScene)?.handleMouseDragged(at: location, viewSize: bounds.size)
    }
    override func mouseUp(with event: NSEvent) {
        (scene as? PetScene)?.handleMouseUp()
    }
    
    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hits = self.hitTest(location, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNTorus || $0.node.geometry is SCNCylinder }
        
        if !validHits.isEmpty {
            (scene as? PetScene)?.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        let hits = self.hitTest(location, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        if !validHits.isEmpty {
            return .copy
        }
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let location = convert(sender.draggingLocation, from: nil)
        let hits = self.hitTest(location, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        if !validHits.isEmpty {
            (scene as? PetScene)?.brain.triggerEating()
            return true
        }
        return false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: PetWindow!
    var scnView: PetSCNView!
    var updateTimer: Timer?
    var statusItem: NSStatusItem?
    var emotionUpdateTimer: Timer?
    var trainingWindow: NSWindow?
    var realtimeDebugWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Automatically verify and start local Ollama LLM, STT, and TTS services if not running
        BackgroundServerManager.shared.ensureServicesRunning()

        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        window = PetWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.hasShadow = false
        
        scnView = PetSCNView(frame: screenRect)
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.wantsLayer = true
        scnView.layer?.isOpaque = false
        scnView.registerForDraggedTypes([.fileURL])
        
        window.contentView = scnView
        
        let scene = PetScene()
        scnView.scene = scene
        scnView.isPlaying = true
        
        window.makeKeyAndOrderFront(nil)
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
        
        setupMenuBar()
        setupKeyboardShortcuts()
        
        // Pop up Byte Control Center window automatically on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openControlCenter(NSMenuItem())
        }
        
        // Menu bar emotion icon updater (every 2 seconds)
        emotionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarEmotion()
        }
        
        // Window open/close observers for Byte reactions
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(windowDidActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(windowDidDeactivate(_:)), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        
        setupNotifications()
    }

    
    // MARK: - Notifications for Q-Learning
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
        
        let goodAction = UNNotificationAction(identifier: "GOOD_ACTION", title: "Good boy!", options: [])
        let badAction = UNNotificationAction(identifier: "BAD_ACTION", title: "Bad path!", options: [])
        
        let category = UNNotificationCategory(identifier: "WALK_FEEDBACK", actions: [goodAction, badAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        guard let state = userInfo["state"] as? Int,
              let actionTaken = userInfo["action"] as? Int,
              let nextState = userInfo["nextState"] as? Int else {
            completionHandler()
            return
        }
        
        var reward: Double = 0.0
        if response.actionIdentifier == "GOOD_ACTION" {
            reward = 1.0
            print("User feedback: Good boy! (+1 reward)")
        } else if response.actionIdentifier == "BAD_ACTION" {
            reward = -1.0
            print("User feedback: Bad path! (-1 reward)")
        }
        
        if reward != 0 {
            QLearningManager.shared.updateQValue(state: state, action: actionTaken, reward: reward, nextState: nextState)
        }
        
        completionHandler()
    }
    
    @objc private func windowDidActivate(_ notification: Notification) {
        guard let scene = scnView?.scene as? PetScene else { return }
        // When a new window comes to focus, occasionally make Byte curious
        if scene.brain.currentAction == .idle && Double.random(in: 0...1) < 0.2 {
            scene.brain.curiosity = min(100, scene.brain.curiosity + 20)
            scene.brain.forceUpdate = true
        }
    }
    
    @objc private func windowDidDeactivate(_ notification: Notification) {
        guard let scene = scnView?.scene as? PetScene else { return }
        // When a window closes/deactivates, occasionally startle Byte
        if scene.brain.currentAction == .idle && Double.random(in: 0...1) < 0.15 {
            scene.brain.triggerStartle()
        }
    }
    
    // MARK: - Menu Bar Emotion Icon
    private func updateMenuBarEmotion() {
        guard let scene = scnView?.scene as? PetScene else { return }
        let emotion = scene.brain.currentEmotion
        let emoji = emotionToEmoji(emotion)
        
        if let button = statusItem?.button {
            button.image = nil
            button.title = emoji
        }
    }
    
    private func emotionToEmoji(_ emotion: PetEmotion) -> String {
        switch emotion {
        case .happy:        return "😊"
        case .sad:          return "😢"
        case .angry:        return "😤"
        case .curious:      return "🧐"
        case .sleepy:       return "😴"
        case .bored:        return "😑"
        case .thinking:     return "🤔"
        case .normal:       return "🤖"
        case .dizzy:        return "😵"
        case .shock:        return "😱"
        case .love:         return "😍"
        case .excited:      return "🤩"
        case .embarrassed:  return "😳"
        case .proud:        return "😎"
        }
    }
    
    // MARK: - Menu Bar Settings
    var settingsWindow: NSWindow?

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Byte Companion")
            if button.image == nil {
                button.title = "🐾"
            }
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🐾 Byte Companion", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let controlCenterItem = NSMenuItem(title: "⚙️ Control Center & Preferences...", action: #selector(openControlCenter(_:)), keyEquivalent: ",")
        menu.addItem(controlCenterItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Pet Modes Sub-Menu
        let modesMenu = NSMenu()
        modesMenu.addItem(NSMenuItem(title: "Auto (Smart Focus)", action: #selector(setModeAuto(_:)), keyEquivalent: ""))
        modesMenu.addItem(NSMenuItem(title: "Work Mode (Quiet)", action: #selector(setModeWork(_:)), keyEquivalent: ""))
        modesMenu.addItem(NSMenuItem(title: "Play Mode (Active)", action: #selector(setModePlay(_:)), keyEquivalent: ""))
        modesMenu.addItem(NSMenuItem(title: "Sleep Mode", action: #selector(setModeSleep(_:)), keyEquivalent: ""))
        
        let modesMenuItem = NSMenuItem(title: "🎯 Companion Mode", action: nil, keyEquivalent: "")
        modesMenuItem.submenu = modesMenu
        menu.addItem(modesMenuItem)
        
        let dropTreatItem = NSMenuItem(title: "🍬 Give Treat", action: #selector(dropTreat(_:)), keyEquivalent: "t")
        menu.addItem(dropTreatItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let muteItem = NSMenuItem(title: "🔇 Mute Voice", action: #selector(toggleMute(_:)), keyEquivalent: "m")
        menu.addItem(muteItem)
        
        let trainingItem = NSMenuItem(title: "🎓 Training HUD Mode", action: #selector(toggleTrainingMode(_:)), keyEquivalent: "")
        trainingItem.state = .off
        menu.addItem(trainingItem)
        
        let debugHudItem = NSMenuItem(title: "💬 Realtime LLM Debugger", action: #selector(toggleRealtimeDebugger(_:)), keyEquivalent: "d")
        menu.addItem(debugHudItem)
        
        #if DEBUG
        menu.addItem(NSMenuItem.separator())
        let animationsMenu = NSMenu()
        let animations: [(String, Int)] = [
            ("Idle", 0), ("Wander / Walk", 1), ("Sleep", 3), ("Jump", 4),
            ("Sit", 5), ("Spin", 6), ("Sit on Corner", 19), ("Sit on Menu Bar", 20),
            ("Climb Window", 21), ("Push Widget", 22), ("Tap Window", 23),
            ("Sneeze", 24), ("Backflip", 25), ("Headbang", 26), ("Wave", 28)
        ]
        for (name, tag) in animations {
            let item = NSMenuItem(title: name, action: #selector(testAnimationClicked(_:)), keyEquivalent: "")
            item.tag = tag
            animationsMenu.addItem(item)
        }
        let animationsMenuItem = NSMenuItem(title: "🎬 Debug Animations", action: nil, keyEquivalent: "")
        animationsMenuItem.submenu = animationsMenu
        menu.addItem(animationsMenuItem)
        #endif
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Byte", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        // Start Focus, Developer Context & Vision monitors
        _ = FocusEngine.shared
        _ = DeveloperContextMonitor.shared
        _ = ByteVisionEngine.shared
    }
    
    @objc private func openControlCenter(_ sender: NSMenuItem) {
        if settingsWindow == nil {
            let view = NSHostingView(rootView: ByteSettingsView())
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Byte Control Center"
            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = view
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func testAnimationClicked(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        let actions: [PetAction] = [
            .idle, .wander, .followCursor, .sleep, .jump, .sit, .spin, .sulk, .dizzy, .tickled,
            .peekWindow, .sitOnTaskbar, .investigate, .stepBack, .dance, .bow, .stretch, .roll, .hide,
            .sitOnCorner, .sitOnMenuBar, .climbWindow, .pushWidget, .tapWindow,
            .sneeze, .backflip, .headbang, .trip, .wave
        ]
        if sender.tag >= 0 && sender.tag < actions.count {
            scene.brain.forceAction(actions[sender.tag])
        }
    }
    
    @objc private func commandClicked(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        let commandActions: [PetAction] = [
            .sitOnCorner, .sitOnMenuBar, .climbWindow, .pushWidget, .tapWindow,
            .backflip, .wave, .headbang, .sneeze, .trip
        ]
        if sender.tag >= 0 && sender.tag < commandActions.count {
            scene.brain.forceAction(commandActions[sender.tag])
        }
    }
    
    @objc private func toggleMute(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        scene.isMuted.toggle()
        scene.brain.isMuted = scene.isMuted
        sender.state = scene.isMuted ? .on : .off
    }
    
    @objc private func toggleCloudAI(_ sender: NSMenuItem) {
        let isCurrentlyCloud = sender.state == .on
        if isCurrentlyCloud {
            AIEngine.shared.provider = LocalOllamaProvider()
            sender.state = .off
        } else {
            AIEngine.shared.provider = GeminiAPIProvider(apiKey: "AQ.Ab8RN6JquuZTkTTYuwK4u8G1zZeUG6NXcKmWbqVohVFvSbyawA")
            sender.state = .on
        }
    }
    
    @objc private func toggleTrainingMode(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        scene.brain.isTrainingMode.toggle()
        let isTraining = scene.brain.isTrainingMode
        sender.state = isTraining ? .on : .off
        
        if isTraining {
            if trainingWindow == nil {
                let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
                let view = NSHostingView(rootView: TrainingFeedbackView(getBrain: { [weak scene] in return scene?.brain }))
                view.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
                
                let win = NSWindow(contentRect: NSRect(x: screenRect.maxX - 220, y: screenRect.maxY - 140, width: 200, height: 120),
                                   styleMask: [.borderless],
                                   backing: .buffered,
                                   defer: false)
                win.isOpaque = false
                win.backgroundColor = .clear
                win.level = .floating
                win.contentView = view
                trainingWindow = win
            }
            trainingWindow?.makeKeyAndOrderFront(nil)
        } else {
            trainingWindow?.orderOut(nil)
        }
    }

    @objc private func toggleRealtimeDebugger(_ sender: NSMenuItem) {
        if realtimeDebugWindow == nil {
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let view = NSHostingView(rootView: RealtimeConversationDebugView())
            view.frame = NSRect(x: 0, y: 0, width: 480, height: 380)

            let win = NSWindow(
                contentRect: NSRect(x: screenRect.maxX - 500, y: screenRect.maxY - 420, width: 480, height: 380),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "⚡ Realtime LLM Debugger & Fine-Tune Inspector"
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.contentView = view
            realtimeDebugWindow = win
        }

        if realtimeDebugWindow?.isVisible == true {
            realtimeDebugWindow?.orderOut(nil)
            sender.state = .off
        } else {
            realtimeDebugWindow?.makeKeyAndOrderFront(nil)
            sender.state = .on
        }
    }
    
    @objc private func dropTreat(_ sender: NSMenuItem) {
        guard let scene = scnView.scene as? PetScene else { return }
        scene.dropTreat()
    }
    
    @objc private func setModeAuto(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .auto
    }
    
    @objc private func setModeWork(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .work
    }
    
    @objc private func setModePlay(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .play
    }
    
    @objc private func setModeSleep(_ sender: NSMenuItem) {
        (scnView.scene as? PetScene)?.brain.currentMode = .sleep
    }
    
    // MARK: - Keyboard Shortcuts
    private var isListeningForPet = false     // Long Command: talk to pet
    private var commandPressTime: Date?       // Tracks when Command was first pressed
    private var commandLongPressTimer: Timer?  // Timer for long-press detection
    private var otherKeyPressed = false        // Tracks if another key was pressed during Command hold
    
    private var eventMonitors: [Any?] = []
    private var keystrokeDates: [Date] = []
    
    private func trackKeystroke() {
        let now = Date()
        keystrokeDates.append(now)
        // Keep only keystrokes from the last 3 seconds
        keystrokeDates = keystrokeDates.filter { now.timeIntervalSince($0) < 3.0 }
        
        if keystrokeDates.count > 15 {
            // Typing fast! (avg > 5 keys/sec over 3 seconds)
            NotificationCenter.default.post(name: NSNotification.Name("UserTypingFast"), object: nil)
            keystrokeDates.removeAll() // Reset to avoid spam
        }
    }
    
    private func setupKeyboardShortcuts() {
        let options = ["AXTrustedCheckOptionPrompt" as NSString: true as NSNumber] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // === FLAGS CHANGED: Detect Command press/release for long-press to talk to pet ===
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            self.handleFlagsChanged(event)
            return event
        })
        
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.handleFlagsChanged(event)
            }
        })
        
        // Detect if any other key is pressed during Command hold to cancel it
        // and track typing speed
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            self.trackKeystroke()
            if event.modifierFlags.contains(.command) {
                self.otherKeyPressed = true
                self.commandLongPressTimer?.invalidate()
            }
            return event
        })
        
        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            self.trackKeystroke()
            if event.modifierFlags.contains(.command) {
                self.otherKeyPressed = true
                self.commandLongPressTimer?.invalidate()
            }
        })
    }
    
    // MARK: - Command Long-Press Detection (Talk to Pet)
    private func handleFlagsChanged(_ event: NSEvent) {
        let commandDown = event.modifierFlags.contains(.command)
        let optionDown = event.modifierFlags.contains(.option)
        
        if let scene = scnView?.scene as? PetScene {
            scene.isLaserPointerActive = optionDown
        }
        
        if commandDown && commandPressTime == nil && !isListeningForPet {
            // Command just pressed — start long-press timer
            commandPressTime = Date()
            otherKeyPressed = false
            commandLongPressTimer?.invalidate()
            commandLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if !self.otherKeyPressed && !self.isListeningForPet {
                    self.beginPetListening()
                }
            }
        } else if !commandDown {
            // Command released
            commandLongPressTimer?.invalidate()
            commandLongPressTimer = nil
            commandPressTime = nil
            
            if isListeningForPet {
                finishPetListening()
            }
        }
    }
    
    // MARK: - Voice Input (Command Long-Press)
    private func beginPetListening() {
        guard !isListeningForPet else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListeningForPet = true
        scene.brain.isListeningToUser = true
        scene.showListeningState(true)
        RealtimeConversationLogger.shared.setListeningState(true)
        VoiceInputManager.shared.startListening { _ in }
    }
    
    private func finishPetListening() {
        guard isListeningForPet else { return }
        guard let scene = scnView.scene as? PetScene else { return }
        isListeningForPet = false
        scene.brain.isListeningToUser = false
        scene.showListeningState(false)
        RealtimeConversationLogger.shared.setListeningState(false)
        
        VoiceInputManager.shared.finishListeningWithResult { transcript in
            if !transcript.isEmpty {
                scene.sayToPet(transcript)
            }
        }
    }
    
    // MARK: - Mouse Position Check
    func checkMousePosition() {
        guard let window = window, let scnView = scnView, let scene = scnView.scene as? PetScene else { return }
        if scene.isDragging { return }
        
        // Fullscreen auto-hide: fade out when a fullscreen app is frontmost
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            // Check if frontmost app is fullscreen by examining its windows
            let isFullscreen = NSApp.presentationOptions.contains(.fullScreen)
            let isSelf = frontApp.bundleIdentifier == Bundle.main.bundleIdentifier
            
            if isFullscreen && !isSelf {
                if window.alphaValue > 0.01 {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.3
                        window.animator().alphaValue = 0.0
                    }
                }
                return  // Don't process mouse events while hidden
            } else if window.alphaValue < 0.99 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    window.animator().alphaValue = 1.0
                }
            }
        }
        
        let mouseLoc = NSEvent.mouseLocation
        let localPoint = window.convertPoint(fromScreen: mouseLoc)
        let viewPoint = scnView.convert(localPoint, from: nil)
        
        let hits = scnView.hitTest(viewPoint, options: [:])
        let validHits = hits.filter { $0.node.geometry is SCNBox || $0.node.geometry is SCNPlane || $0.node.geometry is SCNCylinder }
        
        if !validHits.isEmpty {
            if window.ignoresMouseEvents { window.ignoresMouseEvents = false }
        } else {
            if !window.ignoresMouseEvents { window.ignoresMouseEvents = true }
        }
    }
}

// MARK: - Autonomous Background Services Manager
class BackgroundServerManager {
    static let shared = BackgroundServerManager()
    
    func ensureServicesRunning() {
        DispatchQueue.global(qos: .utility).async {
            self.ensureOllamaRunning()
            self.ensureWhisperServerRunning()
            self.ensureTTSServerRunning()
            self.ensureFlorenceVisionServerRunning()
        }
    }
    
    private func ensureOllamaRunning() {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
        request.httpMethod = "GET"
        
        let sema = DispatchSemaphore(value: 0)
        var isRunning = false
        
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                isRunning = true
            }
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 2.5)
        
        if !isRunning {
            print("🚀 [BackgroundServerManager] Starting local Ollama server...")
            let proc = Process()
            var ollamaPath = "/usr/local/bin/ollama"
            if !FileManager.default.fileExists(atPath: ollamaPath) {
                ollamaPath = "/opt/homebrew/bin/ollama"
            }
            if FileManager.default.fileExists(atPath: ollamaPath) {
                proc.executableURL = URL(fileURLWithPath: ollamaPath)
                proc.arguments = ["serve"]
                try? proc.run()
            }
        }
    }
    
    private func ensureWhisperServerRunning() {
        guard let url = URL(string: "http://localhost:9000/health") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
        request.httpMethod = "GET"
        
        let sema = DispatchSemaphore(value: 0)
        var isRunning = false
        
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                isRunning = true
            }
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 2.5)
        
        if !isRunning {
            let rootPath = "/Users/shanacoder/Documents/Byte"
            let venvPy = "\(rootPath)/.venv/bin/python3"
            let scriptPath = "\(rootPath)/backend/whisper_server.py"
            if FileManager.default.fileExists(atPath: scriptPath) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: venvPy) ? venvPy : "/usr/bin/python3")
                proc.arguments = [scriptPath]
                try? proc.run()
            }
        }
    }

    private func ensureTTSServerRunning() {
        guard let url = URL(string: "http://localhost:8000/health") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
        request.httpMethod = "GET"
        
        let sema = DispatchSemaphore(value: 0)
        var isRunning = false
        
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                isRunning = true
            }
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 2.5)
        
        if !isRunning {
            let rootPath = "/Users/shanacoder/Documents/Byte"
            let venvPy = "\(rootPath)/.venv/bin/python3"
            let scriptPath = "\(rootPath)/backend/tts_server.py"
            if FileManager.default.fileExists(atPath: scriptPath) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: venvPy) ? venvPy : "/usr/bin/python3")
                proc.arguments = [scriptPath]
                try? proc.run()
            }
        }
    }

    private func ensureFlorenceVisionServerRunning() {
        guard let url = URL(string: "http://localhost:9005/health") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2.0)
        request.httpMethod = "GET"
        
        let sema = DispatchSemaphore(value: 0)
        var isRunning = false
        
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                isRunning = true
            }
            sema.signal()
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 2.5)
        
        if !isRunning {
            let rootPath = "/Users/shanacoder/Documents/Byte"
            let venvPy = "\(rootPath)/.venv/bin/python3"
            let scriptPath = "\(rootPath)/backend/florence_vision_server.py"
            if FileManager.default.fileExists(atPath: scriptPath) {
                print("🚀 [BackgroundServerManager] Starting Florence-2-Base (232M) Vision Server on port 9005...")
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: venvPy) ? venvPy : "/usr/bin/python3")
                proc.arguments = [scriptPath]
                try? proc.run()
            }
        }
    }
}

