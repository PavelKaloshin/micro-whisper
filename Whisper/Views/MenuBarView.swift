import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status section
            HStack {
                statusIndicator
                Text(appState.statusText)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Record button
            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                        .foregroundColor(appState.isRecording ? .red : .primary)
                    Text(appState.isRecording ? "Stop Recording" : "Start Recording")
                    Spacer()
                    Text("⌘⇧9")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(appState.processingState == .transcribing || appState.processingState == .processing)
            
            Divider()
            
            // Last transcription preview
            if !appState.lastProcessedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Result:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.lastProcessedText)
                        .font(.caption)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Button(action: copyLastResult) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Last Result")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Divider()
            }
            
            // Settings
            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                    Spacer()
                    Text("⌘,")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
            // Quit
            Button(action: { NSApp.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit Whisper")
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch appState.processingState {
        case .idle:
            return .green
        case .recording:
            return .red
        case .transcribing, .processing:
            return .orange
        case .showingResult:
            return .purple
        case .error:
            return .red
        }
    }
    
    private func toggleRecording() {
        if appState.isRecording {
            Task {
                await appState.stopRecordingAndProcess()
            }
        } else {
            appState.startRecording()
        }
    }
    
    private func copyLastResult() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.lastProcessedText, forType: .string)
    }
    
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}

