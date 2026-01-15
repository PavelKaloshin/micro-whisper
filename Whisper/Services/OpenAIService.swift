import Foundation

class OpenAIService {
    private let baseURL = "https://api.openai.com/v1"
    
    private var apiKey: String? {
        KeychainService.shared.getAPIKey()
    }
    
    // MARK: - Whisper Transcription
    /// Transcribes audio to text
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - language: ISO-639-1 language code (e.g. "ru", "en") or nil for auto-detect
    func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
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
        
        // Add audio file
        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
        
        // Build request body - use search model if web search is enabled
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
            "model": "gpt-4o",  // GPT-4o supports vision
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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

