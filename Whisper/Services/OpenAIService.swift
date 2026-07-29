import Foundation

/// The OpenAI calls AppState depends on. A protocol so tests can inject a stub
/// and exercise the per-mode processing without hitting the network.
protocol OpenAIServicing {
    func transcribe(audioURL: URL, language: String?, prompt: String?) async throws -> String
    func chat(userMessage: String, history: [(role: String, content: String)], systemPrompt: String, model: String, enableWebSearch: Bool) async throws -> String
    func chatWithImage(userMessage: String, imageData: Data, systemPrompt: String) async throws -> String
    func postProcess(text: String, prompt: String, model: String) async throws -> String
}

extension OpenAIService: OpenAIServicing {}

class OpenAIService {
    private let baseURL: String
    private let session: URLSession
    private let apiKeyProvider: () -> String?

    /// Dependency-injection seam for tests: pass a stub `URLSession` (e.g. backed
    /// by a custom `URLProtocol`), an override `baseURL`, and/or a fake key provider.
    /// The defaults reproduce production behavior (real API URL, shared session,
    /// key from the Keychain), so existing callers (`OpenAIService()`) are unchanged.
    init(baseURL: String = "https://api.openai.com/v1",
         session: URLSession = .shared,
         apiKeyProvider: @escaping () -> String? = { KeychainService.shared.getAPIKey() }) {
        self.baseURL = baseURL
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    private var apiKey: String? {
        apiKeyProvider()
    }

    /// MIME type for an audio file extension, for the transcription multipart upload.
    /// Covers the formats Whisper accepts; falls back to a generic audio type.
    static func audioMIMEType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "m4a", "mp4": return "audio/m4a"
        case "wav":        return "audio/wav"
        case "mp3", "mpga": return "audio/mpeg"
        case "flac":       return "audio/flac"
        case "ogg", "oga": return "audio/ogg"
        case "webm":       return "audio/webm"
        default:           return "audio/m4a"
        }
    }

    // MARK: - Whisper Transcription
    /// Transcribes audio to text
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - language: ISO-639-1 language code (e.g. "ru", "en") or nil for auto-detect
    ///   - prompt: Optional prompt to guide the transcription (e.g. terminology)
    func transcribe(audioURL: URL, language: String? = nil, prompt: String? = nil) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add language parameter if specified (prevents unwanted translation)
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Add prompt parameter if specified
        if let prompt = prompt {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // Add audio file. Whisper picks its decoder from the filename extension, so
        // send the real name/MIME (production records .m4a; tests feed a .wav fixture).
        let audioData = try Data(contentsOf: audioURL)
        let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension.lowercased()
        let filename = "audio.\(ext)"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(Self.audioMIMEType(forExtension: ext))\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorResponse.error.message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.text
    }
    
    // MARK: - GPT Post-Processing
    func postProcess(text: String, prompt: String, model: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: prompt),
                ChatMessage(role: "user", content: text)
            ],
            temperature: 0.3
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorResponse.error.message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? text
    }
    
    // MARK: - Chat with History
    func chat(
        userMessage: String,
        history: [(role: String, content: String)],
        systemPrompt: String,
        model: String,
        enableWebSearch: Bool = false
    ) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array
        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        
        // Add conversation history
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        
        // Add current user message
        messages.append(["role": "user", "content": userMessage])
        
        // Build request body - use search model if web search is enabled.
        // NOTE: `gpt-4o-search-preview` + `web_search_options` is the legacy 2025
        // web-search path. The modern approach is the `web_search` tool on a
        // frontier model (gpt-5.x). Left as-is to avoid breaking Ask/Respond/Code/
        // Process blind — verify against the API (key) and migrate to the tool.
        var requestBody: [String: Any] = [
            "model": enableWebSearch ? "gpt-4o-search-preview" : model,
            "messages": messages
        ]
        
        if enableWebSearch {
            // Add web_search_options to enable browsing
            requestBody["web_search_options"] = [String: Any]()
        } else {
            requestBody["temperature"] = 0.7
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorResponse.error.message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
    
    // MARK: - Vision Chat (for image processing)
    func chatWithImage(
        userMessage: String,
        imageData: Data,
        systemPrompt: String
    ) async throws -> String {
        guard let apiKey = apiKey else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert image to base64
        let base64Image = imageData.base64EncodedString()
        
        // Build the request body manually for vision API
        let requestBody: [String: Any] = [
            "model": "gpt-5.4",  // vision-capable (image input); replaces legacy gpt-4o
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userMessage],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorResponse.error.message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }
        
        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
}

// MARK: - Request/Response Models
struct TranscriptionResponse: Codable {
    let text: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionResponse: Codable {
    let choices: [ChatChoice]
}

struct ChatChoice: Codable {
    let message: ChatMessage
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
}

// MARK: - Errors
enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your OpenAI API key in Settings."
        case .invalidResponse:
            return "Invalid response from OpenAI API."
        case .httpError(let code):
            return "HTTP error \(code) from OpenAI API."
        case .apiError(let message):
            return message
        }
    }
}

