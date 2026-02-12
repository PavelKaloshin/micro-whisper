import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isSavingKey: Bool = false
    @State private var keySaveMessage: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLoginService.shared.isEnabled
    @State private var newTerm: String = ""
    
    // Hotkey recording
    @State private var isRecordingHotkey: Bool = false
    @State private var hotkeyMonitor: Any?
    @AppStorage("hotkeyKeyCode") private var savedKeyCode: Int = 25 // 9 key
    @AppStorage("hotkeyModifiers") private var savedModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    
    private let pasteService = PasteService()
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            terminologyTab
                .tabItem {
                    Label("Terms", systemImage: "text.book.closed")
                }
            
            apiTab
                .tabItem {
                    Label("API", systemImage: "key")
                }
            
            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadAPIKey()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section("Whisper Transcription") {
                Picker("Language", selection: $appState.whisperLanguage) {
                    Text("Auto-detect (0)").tag("auto")
                    Text("English (1)").tag("en")
                    Text("Russian (2)").tag("ru")
                }
                
                Text("During recording: press 0 for auto, 1 for English, 2 for Russian.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("GPT Post-Processing") {
                Toggle("Enable GPT post-processing", isOn: $appState.enableGPTProcessing)
                
                Picker("Model", selection: $appState.gptModel) {
                    Text("GPT-4o Mini (Faster, Cheaper)").tag("gpt-4o-mini")
                    Text("GPT-4o (Better Quality)").tag("gpt-4o")
                }
                .disabled(!appState.enableGPTProcessing)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post-processing Prompt:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $appState.postProcessingPrompt)
                        .font(.body)
                        .frame(height: 100)
                        .border(Color.gray.opacity(0.3), width: 1)
                }
                .disabled(!appState.enableGPTProcessing)
                
                Button("Reset to Default") {
                    appState.postProcessingPrompt = "Fix grammar, punctuation, and formatting. Keep the original meaning and style. Return only the corrected text without explanations."
                }
                .disabled(!appState.enableGPTProcessing)
            }
            
            Section("Keyboard Shortcut") {
                HStack {
                    Text("Primary:")
                    Spacer()
                    Text(appState.globeKeyDoublePressOnly ? "🌐🌐 (double Globe)" : "🌐 (single Globe)")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Toggle("Require double press", isOn: $appState.globeKeyDoublePressOnly)
                
                HStack {
                    Text("Fallback:")
                    Spacer()
                    
                    Button(action: {
                        if isRecordingHotkey {
                            stopRecordingHotkey()
                        } else {
                            startRecordingHotkey()
                        }
                    }) {
                        Text(isRecordingHotkey ? "Press keys..." : hotkeyDisplayString)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(minWidth: 80)
                            .background(isRecordingHotkey ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isRecordingHotkey ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Text(appState.globeKeyDoublePressOnly
                     ? "Double-press Globe key or use the fallback shortcut to start/stop recording."
                     : "Single-press Globe key or use the fallback shortcut to start/stop recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        _ = LaunchAtLoginService.shared.setEnabled(newValue)
                    }
                
                Text("Whisper will start automatically when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Terminology Tab
    private var terminologyTab: some View {
        Form {
            Section("Custom Terminology") {
                Text("Add domain-specific terms that often get misheard during transcription. GPT will correct them automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Add Term") {
                HStack {
                    TextField("New term (e.g. Kubernetes, PostgreSQL)", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Add") {
                        addTerm()
                    }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            
            Section("Terms List (\(appState.customTerminology.count))") {
                if appState.customTerminology.isEmpty {
                    Text("No terms added yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(appState.customTerminology, id: \.self) { term in
                                HStack {
                                    Text(term)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer(minLength: 20)
                                    Button(action: { removeTerm(term) }) {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                Divider()
                            }
                        }
                    }
                    .frame(height: 200)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                
                if !appState.customTerminology.isEmpty {
                    HStack {
                        Button("Clear All") {
                            appState.customTerminology = []
                        }
                        .foregroundColor(.red)
                        
                        Spacer()
                        
                        Text("\(appState.customTerminology.count) terms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        
        var terms = appState.customTerminology
        if !terms.contains(term) {
            terms.append(term)
            terms.sort()
            appState.customTerminology = terms
        }
        newTerm = ""
    }
    
    private func removeTerm(_ term: String) {
        var terms = appState.customTerminology
        terms.removeAll { $0 == term }
        appState.customTerminology = terms
    }
    
    // MARK: - API Tab
    private var apiTab: some View {
        Form {
            Section("OpenAI API Key") {
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty)
                    
                    if !keySaveMessage.isEmpty {
                        Text(keySaveMessage)
                            .font(.caption)
                            .foregroundColor(keySaveMessage.contains("✓") ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Button("Delete Key") {
                        deleteAPIKey()
                    }
                    .foregroundColor(.red)
                }
                
                Text("Your API key is stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("Get an API key from OpenAI →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
            
            Section("API Status") {
                HStack {
                    Circle()
                        .fill(appState.hasAPIKey ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.hasAPIKey ? "API key configured" : "No API key")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Permissions Tab
    private var permissionsTab: some View {
        Form {
            Section("Required Permissions") {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Microphone")
                            .font(.headline)
                        Text("Required to record your voice")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Granted on first use")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("Accessibility")
                            .font(.headline)
                        Text("Required to auto-paste transcribed text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    if pasteService.hasAccessibilityPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Button("Grant Access") {
                            pasteService.promptForAccessibilityPermission()
                        }
                    }
                }
            }
            
            Section {
                Text("Without Accessibility permission, text will be copied to clipboard but won't auto-paste. You'll need to manually paste with ⌘V.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Open System Settings → Privacy & Security") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Actions
    private func loadAPIKey() {
        if let key = KeychainService.shared.getAPIKey() {
            apiKey = key
        }
    }
    
    private func saveAPIKey() {
        isSavingKey = true
        if KeychainService.shared.saveAPIKey(apiKey) {
            keySaveMessage = "✓ Saved"
        } else {
            keySaveMessage = "Failed to save"
        }
        isSavingKey = false
        
        // Clear message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            keySaveMessage = ""
        }
    }
    
    private func deleteAPIKey() {
        KeychainService.shared.deleteAPIKey()
        apiKey = ""
        keySaveMessage = "Key deleted"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            keySaveMessage = ""
        }
    }
    
    // MARK: - Hotkey Recording
    private var hotkeyDisplayString: String {
        var parts: [String] = []
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(savedModifiers))
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        let keyName = keyCodeToString(UInt16(savedKeyCode))
        parts.append(keyName)
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
            105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4",
            119: "F2", 120: "F1", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "?"
    }
    
    private func startRecordingHotkey() {
        isRecordingHotkey = true
        
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore modifier-only presses
            guard event.keyCode != 0 else { return event }
            
            // Save the new hotkey
            self.savedKeyCode = Int(event.keyCode)
            self.savedModifiers = Int(event.modifierFlags.intersection([.command, .option, .shift, .control]).rawValue)
            
            // Update AppDelegate
            AppDelegate.shared?.updateHotKey(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
            
            self.stopRecordingHotkey()
            return nil
        }
    }
    
    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}

