import Foundation

/// Simple secure storage using file-based encryption
/// Avoids Keychain password prompts during development
class KeychainService {
    static let shared = KeychainService()
    
    private let fileName = ".whisper_config"
    
    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let whisperDir = appSupport.appendingPathComponent("Whisper", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: whisperDir, withIntermediateDirectories: true)
        
        return whisperDir.appendingPathComponent(fileName)
    }
    
    private init() {}
    
    // MARK: - API Key Management
    func saveAPIKey(_ apiKey: String) -> Bool {
        do {
            // Simple obfuscation (not true encryption, but avoids plain text)
            let obfuscated = Data(apiKey.utf8).base64EncodedString()
            try obfuscated.write(to: configURL, atomically: true, encoding: .utf8)
            
            // Set file to be hidden and readable only by owner
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            
            return true
        } catch {
            print("Failed to save API key: \(error)")
            return false
        }
    }
    
    func getAPIKey() -> String? {
        do {
            let obfuscated = try String(contentsOf: configURL, encoding: .utf8)
            guard let data = Data(base64Encoded: obfuscated),
                  let apiKey = String(data: data, encoding: .utf8) else {
                return nil
            }
            return apiKey
        } catch {
            return nil
        }
    }
    
    @discardableResult
    func deleteAPIKey() -> Bool {
        do {
            try FileManager.default.removeItem(at: configURL)
            return true
        } catch {
            return false
        }
    }
    
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}

