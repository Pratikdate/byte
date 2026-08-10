import SwiftUI

struct ByteSettingsView: View {
    @State private var selectedTab = 0
    @State private var isMuted: Bool = false
    @State private var petMode: String = "Auto"
    @State private var useCloudAI: Bool = false
    @State private var focusEngineStatus: String = "Active"
    @State private var activePersonality: PersonalityProfile = SettingsManager.shared.activePersonality
    @State private var activeTheme: ByteTheme = SettingsManager.shared.activeTheme
    
    @State private var memoriesList: [String] = []
    @State private var behavioralRules: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Image(systemName: "pawprint.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(Color.cyan)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Byte Control Center")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Autonomous Developer Companion")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.4))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Custom Tab Bar
            HStack(spacing: 16) {
                TabButton(title: "Companion", icon: "person.circle.fill", index: 0, selectedTab: $selectedTab)
                TabButton(title: "Developer Focus", icon: "brain.head.profile", index: 1, selectedTab: $selectedTab)
                TabButton(title: "AI Engine", icon: "cpu.fill", index: 2, selectedTab: $selectedTab)
                TabButton(title: "Memory Graph", icon: "externaldrive.connected.to.line.below.fill", index: 3, selectedTab: $selectedTab)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.2))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Content Area
            ScrollView {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        companionTab
                    } else if selectedTab == 1 {
                        focusTab
                    } else if selectedTab == 2 {
                        aiTab
                    } else {
                        memoryTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 420)
        .background(
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                LinearGradient(colors: [Color.cyan.opacity(0.08), Color.purple.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .onAppear {
            loadSettingsData()
        }
    }
    
    // MARK: - Tabs
    
    private var companionTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Body Theme & Appearance", icon: "paintbrush.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Theme Dropdown", selection: $activeTheme) {
                        ForEach(ByteTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: activeTheme) { newValue in
                        SettingsManager.shared.activeTheme = newValue
                    }
                    .tint(.cyan)
                    
                    // Visual Theme Swatches Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ByteTheme.allCases) { theme in
                            Button(action: {
                                activeTheme = theme
                                SettingsManager.shared.activeTheme = theme
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(theme.shellColor))
                                        .overlay(Circle().stroke(Color(theme.eyeColor), lineWidth: 2))
                                        .frame(width: 14, height: 14)
                                    Text(theme.rawValue)
                                        .font(.system(size: 11, weight: activeTheme == theme ? .bold : .regular))
                                        .foregroundColor(activeTheme == theme ? .white : .white.opacity(0.7))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(activeTheme == theme ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(activeTheme == theme ? Color.cyan : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }

            SettingsCard(title: "Personality Profile", icon: "face.smiling") {
                Picker("Personality", selection: $activePersonality) {
                    ForEach(PersonalityProfile.allCases, id: \.self) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: activePersonality) { newValue in
                    SettingsManager.shared.activePersonality = newValue
                }
                .tint(.cyan)
            }
            
            SettingsCard(title: "Activity Mode", icon: "slider.horizontal.3") {
                Picker("Behavior Profile", selection: $petMode) {
                    Text("Auto (Smart Focus)").tag("Auto")
                    Text("Work Mode (Quiet)").tag("Work")
                    Text("Play Mode (Active)").tag("Play")
                    Text("Sleep Mode").tag("Sleep")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            SettingsCard(title: "Audio & Speech", icon: "speaker.wave.2.fill") {
                Toggle("Mute Voice Output", isOn: $isMuted)
                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                    .onChange(of: isMuted) { newValue in
                        AudioManager.shared.stopSpeaking()
                    }
            }
        }
    }
    
    private var focusTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Developer Context", icon: "laptopcomputer") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active IDE / App:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(DeveloperContextMonitor.shared.currentContext.activeAppName.isEmpty ? "None" : DeveloperContextMonitor.shared.currentContext.activeAppName)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                    }
                    HStack {
                        Text("Detected Language:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(DeveloperContextMonitor.shared.currentContext.detectedLanguage)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                    HStack {
                        Text("Current Focus State:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(FocusEngine.shared.currentFocusLevel.rawValue.capitalized)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Visual Vision Engine:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(ByteVisionEngine.shared.activeEngineName)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("Perception Mode:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("Event-Driven & On-Demand (0% Idle)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Visual Perception Context:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(ByteVisionEngine.shared.formattedVisionContextForAI())
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
    
    private var aiTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "LLM & Voice Pipeline", icon: "brain") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Use Gemini Cloud API (Fallback)", isOn: $useCloudAI)
                        .toggleStyle(SwitchToggleStyle(tint: .cyan))
                        .onChange(of: useCloudAI) { newValue in
                            if newValue {
                                AIEngine.shared.provider = GeminiAPIProvider(apiKey: "AQ.Ab8RN6JquuZTkTTYuwK4u8G1zZeUG6NXcKmWbqVohVFvSbyawA")
                            } else {
                                AIEngine.shared.provider = LocalOllamaProvider()
                            }
                        }
                    
                    HStack {
                        Text("Active LLM Model:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(useCloudAI ? "Gemini 2.5 Flash" : "Ollama LLaMA 3.2 (Local)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    HStack {
                        Text("Vision Model:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("Florence-2-Base (232M / Port 9005)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("STT Engine:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("faster-whisper (Port 9000)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("TTS Engine:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("Kokoro-82M (Port 8000)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
    }
    
    private var memoryTab: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Learned Behavioral Rules", icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 6) {
                    let rules = MemoryGraph.shared.getBehavioralRulesString()
                    Text(rules)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            
            SettingsCard(title: "Personal Facts Learned", icon: "text.badge.checkmark") {
                VStack(alignment: .leading, spacing: 6) {
                    let facts = MemoryGraph.shared.getUserFactsString()
                    Text(facts)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }
    
    private func loadSettingsData() {
        // Hydrate data from singletons
        activePersonality = SettingsManager.shared.activePersonality
        activeTheme = SettingsManager.shared.activeTheme
    }
}

// MARK: - Helper Views

struct TabButton: View {
    let title: String
    let icon: String
    let index: Int
    @Binding var selectedTab: Int
    
    var isSelected: Bool { selectedTab == index }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.cyan.opacity(0.2) : Color.clear)
            .foregroundColor(isSelected ? .cyan : .white.opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.cyan.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.cyan)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            Divider()
                .background(Color.white.opacity(0.1))
            content
        }
        .padding(14)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
