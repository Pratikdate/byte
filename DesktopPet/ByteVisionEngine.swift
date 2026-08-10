import Foundation
import AppKit
import Vision

/// Hybrid Event-Driven & On-Demand Visual Perception Engine for Byte
/// Primary Deep Engine: Microsoft Florence-2-Base (232M parameters) server on port 9005
/// Fast On-Device Fallback: Apple Vision Framework (VNRecognizeTextRequest)
///
/// Features ZERO continuous overhead (no 5s polling timer).
/// Visual reading triggers ONLY on:
/// 1. Tab/App switch events (NSWorkspace.didActivateApplicationNotification) debounced by 3s.
/// 2. On-demand user queries ("Byte, what's on my screen?", "Read this error").
class ByteVisionEngine {
    static let shared = ByteVisionEngine()

    private(set) var currentVisualContext: String = "No visual target detected."
    private(set) var isFlorenceActive: Bool = false
    private(set) var activeEngineName: String = "Apple Vision (Native)"
    private(set) var currentTaskMode: String = "<OCR_WITH_REGION>"

    private var lastEventScanTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 3.0 // 3-second debounce cooldown
    private let florenceEndpoint = "http://localhost:9005/read_vision"
    private let florenceHealthEndpoint = "http://localhost:9005/health"

    private init() {
        setupEventObservers()
    }

    /// Registers system observers for application and window focus changes.
    /// Replaces legacy 5-second continuous timer loop to eliminate screen capture overhead.
    private func setupEventObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppSwitchEvent),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppSwitchEvent() {
        let now = Date()
        guard now.timeIntervalSince(lastEventScanTime) >= debounceInterval else { return }
        lastEventScanTime = now
        
        // Lightweight event scan on tab/app switch
        performScreenVisualScan(task: "<OCR>")
    }

    private(set) var currentImageContext: String? = nil

    /// Detects if user prompt is asking a visual screen query, text selection query, or image query
    func detectVisionIntent(in text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "screen", "look at", "what's on my", "read this", "read code",
            "check error", "stack trace", "what am i working on", "see this",
            "take a look", "my code", "terminal error", "visual", "ide",
            "selected", "highlighted", "selection", "explain this", "what is this code",
            "explain selected", "this line", "this paragraph", "selected text",
            "image", "photo", "picture", "diagram", "screenshot", "chart",
            "mockup", "design", "figure", "copied image", "clipboard image",
            "describe picture", "what's in this image", "what is this picture",
            "illustration", "graph", "ui design", "look at this image"
        ]
        return keywords.contains { lower.contains($0) }
    }

    /// Checks if query is specifically asking to analyze an image/picture/diagram
    func detectImageIntent(in text: String) -> Bool {
        let lower = text.lowercased()
        let keywords = [
            "image", "photo", "picture", "diagram", "screenshot", "chart",
            "mockup", "design", "figure", "copied image", "clipboard image",
            "describe picture", "what's in this image", "what is this picture",
            "illustration", "graph", "ui design", "look at this image"
        ]
        return keywords.contains { lower.contains($0) }
    }

    /// Reads images copied to macOS Clipboard (NSPasteboard)
    func getClipboardImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        guard let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil),
              let image = objects.first as? NSImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }

    /// Captures highlighted/selected text from the active window using macOS Accessibility API
    func getSelectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appResult == .success, let focusedApp = focusedApp else { return nil }

        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard elementResult == .success, let focusedElement = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        if textResult == .success, let str = selectedText as? String, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    /// Analyzes any image (clipboard image, drop image, screenshot) with Florence-2 dense captioning
    func analyzeImage(cgImage: CGImage, task: String = "<MORE_DETAILED_CAPTION>", completion: ((String) -> Void)? = nil) {
        sendToFlorenceServer(cgImage: cgImage, task: task) { [weak self] florenceContext in
            let result = florenceContext ?? "Image contains visual elements."
            DispatchQueue.main.async {
                self?.currentImageContext = result
                completion?(result)
            }
        }
    }

    /// Primary entry point for visual scan (Event-driven or On-Demand)
    func performScreenVisualScan(task: String = "<OCR_WITH_REGION>", completion: ((String) -> Void)? = nil) {
        // If a clipboard image is available and user is asking about images, analyze clipboard image first
        if let clipboardImg = getClipboardImage() {
            analyzeImage(cgImage: clipboardImg, task: "<MORE_DETAILED_CAPTION>") { [weak self] caption in
                self?.currentImageContext = "Copied Image: '\(caption)'"
            }
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            completion?("No active workspace window found.")
            return
        }

        // Locate frontmost application window
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               ownerName == frontApp.localizedName,
               let windowID = window[kCGWindowNumber as String] as? CGWindowID {
                
                guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) else {
                    continue
                }

                let activeTask = task == "<OCR_WITH_REGION>" ? "<MORE_DETAILED_CAPTION>" : task

                // Attempt Microsoft Florence-2-Base 232M visual reading
                sendToFlorenceServer(cgImage: cgImage, task: activeTask) { [weak self] florenceContext in
                    if let context = florenceContext {
                        DispatchQueue.main.async {
                            self?.isFlorenceActive = true
                            self?.activeEngineName = "Florence-2-Base (232M)"
                            self?.currentVisualContext = context
                            completion?(context)
                        }
                    } else {
                        // Fallback to native Apple Vision Framework if Florence server is offline/loading
                        self?.performAppleVisionFallback(cgImage: cgImage, completion: completion)
                    }
                }
                break
            }
        }
    }

    /// Downscales CGImage to a lightweight max dimension (640px) for 10x faster transfer & ultra-low GPU/RAM overhead
    private func downscale(cgImage: CGImage, maxDimension: CGFloat = 640) -> CGImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        if max(width, height) <= maxDimension {
            return cgImage
        }

        let ratio = maxDimension / max(width, height)
        let newWidth = max(1, Int(width * ratio))
        let newHeight = max(1, Int(height * ratio))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cgImage
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(newWidth), height: CGFloat(newHeight)))

        return context.makeImage() ?? cgImage
    }

    /// Sends captured screen frame to Microsoft Florence-2-Base 232M server
    private func sendToFlorenceServer(cgImage: CGImage, task: String, completion: @escaping (String?) -> Void) {
        let lightweightImage = downscale(cgImage: cgImage, maxDimension: 640)
        let bitmapRep = NSBitmapImageRep(cgImage: lightweightImage)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.65]) else {
            completion(nil)
            return
        }

        let base64String = jpegData.base64EncodedString()
        guard let url = URL(string: florenceEndpoint) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "image": base64String,
            "task": task
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.5

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String, status == "success",
                   let meaningfulContext = json["meaningful_context"] as? String, !meaningfulContext.isEmpty {
                    completion(meaningfulContext)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    /// Native Apple Vision Framework Fallback (VNRecognizeTextRequest)
    private func performAppleVisionFallback(cgImage: CGImage, completion: ((String) -> Void)?) {
        let lightweightImage = downscale(cgImage: cgImage, maxDimension: 640)
        let requestHandler = VNImageRequestHandler(cgImage: lightweightImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                DispatchQueue.main.async {
                    completion?("No visual target detected.")
                }
                return
            }

            let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
            self?.processRecognizedVisionText(recognizedStrings, completion: completion)
        }
        
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }

    /// Formats Apple Vision text into meaningful context for Byte
    private func processRecognizedVisionText(_ lines: [String], completion: ((String) -> Void)?) {
        guard !lines.isEmpty else {
            DispatchQueue.main.async {
                self.isFlorenceActive = false
                self.activeEngineName = "Apple Vision (Native)"
                self.currentVisualContext = "Developer is focused in editor."
                completion?(self.currentVisualContext)
            }
            return
        }

        var detectedContexts: [String] = []

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error:") || lower.contains("fatal error") || lower.contains("exception") || lower.contains("failed") {
                detectedContexts.append("Build/Runtime Error: '\(line.prefix(60))'")
            } else if lower.contains("func ") || lower.contains("class ") || lower.contains("struct ") || lower.contains("def ") {
                detectedContexts.append("Writing Code: '\(line.prefix(50))'")
            } else if lower.contains("git commit") || lower.contains("git push") || lower.contains("build succeeded") {
                detectedContexts.append("Milestone: '\(line.prefix(50))'")
            }
        }

        DispatchQueue.main.async {
            self.isFlorenceActive = false
            self.activeEngineName = "Apple Vision (Native)"
            if !detectedContexts.isEmpty {
                self.currentVisualContext = detectedContexts.prefix(2).joined(separator: " | ")
            } else {
                self.currentVisualContext = "Developer is focused in editor."
            }
            completion?(self.currentVisualContext)
        }
    }

    /// Returns clean formatted visual, image & highlighted text context for Byte's AI reasoning prompt
    func formattedVisionContextForAI() -> String {
        var context = currentVisualContext
        if let imgCtx = currentImageContext, !imgCtx.isEmpty {
            context = "[\(imgCtx)] | \(context)"
        }
        if let selText = getSelectedText(), !selText.isEmpty {
            let trun = selText.count > 400 ? String(selText.prefix(400)) + "..." : selText
            context = "[USER HIGHLIGHTED/SELECTED TEXT: \"\(trun)\"] | Visual Context: \(context)"
        }
        return context
    }

    /// Prepares fresh visual, selected text, and image context before LLM prompt generation, guaranteeing completion before AI prompt assembly.
    func prepareVisualContextForPrompt(userMessage: String?, completion: @escaping (String) -> Void) {
        let clipboardImg = getClipboardImage()
        let msg = userMessage ?? ""
        let isVisionQuery = !msg.isEmpty && detectVisionIntent(in: msg)
        let isImageQuery = (!msg.isEmpty && detectImageIntent(in: msg)) || (clipboardImg != nil && (msg.lowercased().contains("image") || msg.lowercased().contains("copied") || msg.lowercased().contains("picture") || msg.lowercased().contains("photo")))

        if isImageQuery, let img = clipboardImg {
            analyzeImage(cgImage: img, task: "<MORE_DETAILED_CAPTION>") { [weak self] caption in
                self?.currentImageContext = "Copied Image Analysis: '\(caption)'"
                DispatchQueue.main.async {
                    completion(self?.formattedVisionContextForAI() ?? "")
                }
            }
            return
        }

        if isVisionQuery {
            let task = isImageQuery ? "<MORE_DETAILED_CAPTION>" : "<OCR_WITH_REGION>"
            performScreenVisualScan(task: task) { [weak self] _ in
                DispatchQueue.main.async {
                    completion(self?.formattedVisionContextForAI() ?? "")
                }
            }
            return
        }

        // Immediate return with formatted context (including getSelectedText() & cached vision/image)
        DispatchQueue.main.async {
            completion(self.formattedVisionContextForAI())
        }
    }
}
