import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which engine refines / translates the transcript after capture.
enum PostProcessingEngine: String, CaseIterable {
    case cloud   // OpenAI GPT (network, best quality)
    case local   // Apple Foundation Models (on-device, private, free)

    var displayName: String {
        switch self {
        case .cloud: return "Cloud (OpenAI GPT)"
        case .local: return "Local (Apple Intelligence)"
        }
    }
}

enum LocalRefinerError: LocalizedError {
    case unavailable
    var errorDescription: String? { "On-device Apple Intelligence model is unavailable." }
}

/// On-device text refinement / translation via Apple's Foundation Models
/// (Apple Intelligence). Available on macOS 26+ on eligible hardware with Apple
/// Intelligence enabled. Falls back to the cloud path when unavailable.
enum LocalRefiner {

    /// Whether the on-device model can be used right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// A short, user-facing explanation when the model is unavailable (for Settings).
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn't support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Enable Apple Intelligence in System Settings to use the local engine."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading — try again shortly."
            case .unavailable:
                return "Apple Intelligence is currently unavailable."
            }
        }
        return "Requires macOS 26 or later."
        #else
        return "This build has no Foundation Models support."
        #endif
    }

    /// Run a single instruction over `text` and return the model's output.
    /// Throws `LocalRefinerError.unavailable` when the model can't be used.
    static func run(text: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw LocalRefinerError.unavailable
    }
}
