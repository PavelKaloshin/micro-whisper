import AppKit
import Carbon.HIToolbox

class PasteService {
    
    private let logFile = "/tmp/whisper_paste.log"
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
        print("PasteService: \(message)")
    }
    
    /// Copies text to clipboard and simulates paste
    func copyAndPaste(text: String) {
        log("copyAndPaste called with text length: \(text.count)")
        
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        log("Clipboard copy success: \(success)")
        
        // Check what's in clipboard
        if let clipboardContent = pasteboard.string(forType: .string) {
            log("Clipboard now contains: \(clipboardContent.prefix(50))...")
        }
        
        // Get frontmost app info
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            log("Frontmost app: \(frontApp.localizedName ?? "unknown") (bundleID: \(frontApp.bundleIdentifier ?? "unknown"))")
        }
        
        // Check accessibility
        let axTrusted = AXIsProcessTrusted()
        log("AXIsProcessTrusted: \(axTrusted)")
        
        // Try AppleScript paste
        log("Attempting AppleScript paste...")
        simulatePasteWithAppleScript()
    }
    
    /// Copies text to clipboard only (no paste)
    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Simulates Cmd+V using AppleScript - most reliable method
    private func simulatePasteWithAppleScript() {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            log("AppleScript executed, result: \(String(describing: result))")
        }
        
        if let error = error {
            log("AppleScript error: \(error)")
            log("Trying CGEvent fallback...")
            simulatePasteWithCGEvent()
        } else {
            log("AppleScript paste completed (no error returned)")
        }
    }
    
    /// Fallback paste method using CGEvent
    private func simulatePasteWithCGEvent() {
        log("CGEvent paste starting...")
        
        let source = CGEventSource(stateID: .combinedSessionState)
        log("CGEventSource created: \(source != nil)")
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            log("Failed to create CGEvents")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cgSessionEventTap)
        usleep(10000) // 10ms delay
        keyUp.post(tap: .cgSessionEventTap)
        
        log("CGEvent paste completed")
    }
    
    /// Prompts user to grant accessibility permission
    func promptForAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Checks if accessibility permission is granted
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
}

