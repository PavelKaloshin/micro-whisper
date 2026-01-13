import Cocoa
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupHotKey()
    }
    
    func setupHotKey() {
        // Default hotkey: Cmd + Shift + 9
        hotKey = HotKey(key: .nine, modifiers: [.command, .shift])
        
        hotKey?.keyDownHandler = { [weak self] in
            self?.toggleRecording()
        }
    }
    
    private func toggleRecording() {
        let appState = AppState.shared
        
        if appState.isRecording {
            // Stop recording and process
            Task {
                await appState.stopRecordingAndProcess()
            }
        } else {
            // Start recording
            appState.startRecording()
        }
    }
    
    func updateHotKey(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.toggleRecording()
        }
    }
}

