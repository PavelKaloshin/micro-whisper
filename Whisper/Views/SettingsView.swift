import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isSavingKey: Bool = false
    @State private var keySaveMessage: String = ""
    
    private let pasteService = PasteService()
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
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
        .frame(width: 500, height: 400)
        .onAppear {
            loadAPIKey()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
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
                    Text("Record Hotkey:")
                    Spacer()
                    Text("⌘ ⇧ 9")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text("Press once to start recording, press again to stop and transcribe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}

