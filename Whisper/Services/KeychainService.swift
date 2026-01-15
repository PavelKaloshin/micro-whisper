import Foundation
import Security

/// Secure storage using macOS Keychain
/// Uses kSecAttrAccessibleWhenUnlocked to avoid password prompts on every access
class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.whisper.openai"
    private let account = "api-key"
    
    private init() {}
    
    // MARK: - API Key Management
    func saveAPIKey(_ apiKey: String) -> Bool {
        // First, try to delete any existing key
        deleteAPIKey()
        
        guard let data = apiKey.data(using: .utf8) else {
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // This is the key: accessible when unlocked, no user interaction required
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("API key saved to Keychain")
            return true
        } else {
            print("Failed to save API key to Keychain: \(status)")
            return false
        }
    }
    
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let apiKey = String(data: data, encoding: .utf8) {
            return apiKey
        }
        
        return nil
    }
    
    @discardableResult
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
    
    // MARK: - Migration from old file-based storage
    func migrateFromFileIfNeeded() {
        // Check if we already have a key in Keychain
        if hasAPIKey {
            return
        }
        
        // Try to migrate from old file-based storage
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldConfigURL = appSupport.appendingPathComponent("Whisper/.whisper_config")
        
        if let obfuscated = try? String(contentsOf: oldConfigURL, encoding: .utf8),
           let data = Data(base64Encoded: obfuscated),
           let apiKey = String(data: data, encoding: .utf8) {
            
            if saveAPIKey(apiKey) {
                // Successfully migrated, delete old file
                try? FileManager.default.removeItem(at: oldConfigURL)
                print("Migrated API key from file to Keychain")
            }
        }
    }
}
