import Foundation
import SwiftUI
import Combine

enum ProcessingState: Equatable {
    case idle
    case recording
    case transcribing
    case processing
    case showingResult(String) // For displaying GPT answers
    case error(String)
}

enum RecordingMode: String, CaseIterable {
    case transcribe = "transcribe"  // Just transcribe and fix
    case askGPT = "askGPT"          // Ask GPT and show answer
    case respond = "respond"        // Respond using clipboard as context
    case code = "code"              // Generate code from voice prompt
    case process = "process"        // Process clipboard content with voice command
    
    var displayName: String {
        switch self {
        case .transcribe: return "📝 Transcribe"
        case .askGPT: return "🤖 Ask"
        case .respond: return "💬 Respond"
        case .code: return "👨‍💻 Code"
        case .process: return "⚙️ Process"
        }
    }
    
    var hotkey: String {
        switch self {
        case .transcribe: return "T"
        case .askGPT: return "A"
        case .respond: return "R"
        case .code: return "C"
        case .process: return "P"
        }
    }
    
    var tooltip: String {
        switch self {
        case .transcribe: return "Transcribe voice to text with formatting"
        case .askGPT: return "Ask GPT a question and get an answer"
        case .respond: return "Use clipboard as context, voice as prompt - generate a response"
        case .code: return "Generate code from voice description (Python/Bash/etc)"
        case .process: return "Process clipboard content with voice command (translate, summarize, etc)"
        }
    }
    
    var usesClipboard: Bool {
        switch self {
        case .respond, .process: return true
        default: return false
        }
    }
    
    var showsResult: Bool {
        switch self {
        case .askGPT, .respond, .code, .process: return true
        case .transcribe: return false
        }
    }
}

enum CodeLanguageMode: String, CaseIterable {
    case auto = "auto"
    case python = "python"
    case bash = "bash"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .python: return "Python"
        case .bash: return "Bash"
        }
    }
    
    var hotkey: String {
        switch self {
        case .auto: return "U"  // aUto
        case .python: return "Y" // pYthon
        case .bash: return "B"
        }
    }
    
    var promptHint: String {
        switch self {
        case .auto: return "Auto-detect the programming language from context."
        case .python: return "Write Python code."
        case .bash: return "Write Bash/shell script."
        }
    }
}

enum FormattingMode: String, CaseIterable {
    case standard = "standard"
    case notion = "notion"
    case slack = "slack"
    
    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .notion: return "Notion"
        case .slack: return "Slack"
        }
    }
    
    var hotkey: String {
        switch self {
        case .standard: return "D"
        case .notion: return "N"
        case .slack: return "S"
        }
    }
    
    var tooltip: String {
        switch self {
        case .standard:
            return "Default formatting: fixes grammar and punctuation while preserving original style"
        case .notion:
            return "Notion style: structured with headings, bullet lists, and clear organization"
        case .slack:
            return "Slack style: ultra-short messages, no filler words, no repeated ideas, no trailing periods"
        }
    }
    
    var prompt: String {
        switch self {
        case .standard:
            return """
            Fix grammar, punctuation, and formatting. Keep the original meaning and style.
            Return only the corrected text without explanations.
            """
        case .notion:
            return """
            Format this text for Notion. Structure it nicely with:
            - Clear headings (use ## for main sections) where appropriate
            - Bullet lists for multiple items or steps
            - Bold for emphasis on key terms
            - Keep it organized and easy to scan
            Return only the formatted text without explanations.
            """
        case .slack:
            return """
            Format this as a short Slack message:
            - Make it as concise as possible - remove ALL filler words (just, actually, basically, really, very, quite, etc.)
            - If the same idea is repeated, keep it only ONCE
            - Don't end with a period (too formal for Slack)
            - Add 1-2 emoji only if truly appropriate
            - Compress long phrases into shorter ones
            - Keep casual but professional tone
            Return only the formatted text, nothing else.
            """
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var processingState: ProcessingState = .idle
    @Published var lastTranscription: String = ""
    @Published var lastProcessedText: String = ""
    @Published var audioLevel: Float = 0
    @Published var recordingMode: RecordingMode = .transcribe
    @Published var formattingMode: FormattingMode = .standard
    @Published var codeLanguageMode: CodeLanguageMode = .auto
    @Published var conversationHistory: [(role: String, content: String)] = []
    @Published var useClipboardContext: Bool = true
    @Published var clipboardContent: ClipboardContent = .empty
    @Published var autoPasteResult: Bool = true // If true, paste result. If false, show in chat.
    
    enum ClipboardContent {
        case empty
        case text(String)
        case image(Data)
        
        var hasContent: Bool {
            switch self {
            case .empty: return false
            default: return true
            }
        }
        
        var preview: String {
            switch self {
            case .empty: return "Empty"
            case .text(let str): 
                let preview = str.prefix(50)
                return preview.count < str.count ? "\(preview)..." : String(preview)
            case .image: return "📷 Image"
            }
        }
    }
    
    // MARK: - Settings
    @AppStorage("gptModel") var gptModel: String = "gpt-4o-mini"
    @AppStorage("postProcessingPrompt") var postProcessingPrompt: String = "Fix grammar, punctuation, and formatting. Keep the original meaning and style. Return only the corrected text without explanations."
    @AppStorage("enableGPTProcessing") var enableGPTProcessing: Bool = true
    @AppStorage("whisperLanguage") var whisperLanguage: String = "auto" // "auto", "ru", "en", etc.
    
    // MARK: - Services
    private let audioRecorder = AudioRecorder()
    private let openAIService = OpenAIService()
    private let pasteService = PasteService()
    private var cancellables = Set<AnyCancellable>()
    
    // Track previous app for restoring focus after recording
    private var previousApp: NSRunningApplication?
    
    private init() {
        // Subscribe to audio level updates
        audioRecorder.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Computed Properties
    var hasAPIKey: Bool {
        KeychainService.shared.getAPIKey() != nil
    }
    
    var statusText: String {
        switch processingState {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .processing:
            return "Processing with GPT..."
        case .showingResult:
            return "Done"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    // MARK: - Clipboard
    func refreshClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Check for image first
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            clipboardContent = .image(imageData)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            clipboardContent = .text(text)
        } else {
            clipboardContent = .empty
        }
    }
    
    // MARK: - Recording Controls
    func startRecording() {
        guard hasAPIKey else {
            processingState = .error("No API key configured")
            RecordingWindowController.shared.showWindow()
            hideWindowAfterDelay()
            return
        }
        
        // If we're showing a result, continue the conversation
        if case .showingResult = processingState {
            recordingMode = .askGPT // Stay in Ask GPT mode
        } else {
            // Save the currently active app BEFORE showing our window
            previousApp = NSWorkspace.shared.frontmostApplication
            // Reset to Transcribe mode (but keep formatting preference)
            recordingMode = .transcribe
            // Clear conversation if starting fresh
            conversationHistory = []
        }
        
        // Refresh clipboard for modes that use it
        if recordingMode.usesClipboard {
            refreshClipboard()
        }
        
        do {
            try audioRecorder.startRecording()
            isRecording = true
            processingState = .recording
            RecordingWindowController.shared.showWindow()
        } catch {
            processingState = .error("Failed to start recording: \(error.localizedDescription)")
            RecordingWindowController.shared.showWindow()
            hideWindowAfterDelay()
        }
    }
    
    func stopRecordingAndProcess() async {
        isRecording = false
        let currentMode = recordingMode
        
        guard let audioURL = audioRecorder.stopRecording() else {
            processingState = .error("No audio recorded")
            hideWindowAfterDelay()
            return
        }
        
        // Transcribe with Whisper
        processingState = .transcribing
        do {
            let language = whisperLanguage == "auto" ? nil : whisperLanguage
            let transcription = try await openAIService.transcribe(audioURL: audioURL, language: language)
            lastTranscription = transcription
            
            var finalText = transcription
            
            switch currentMode {
            case .askGPT:
                // Ask GPT mode - get an answer with conversation history
                processingState = .processing
                let systemPrompt = """
                You are a helpful voice assistant. The user speaks to you via voice, and you answer their questions.
                You have access to web search for current information.
                Answer concisely and helpfully. Use markdown formatting for better readability (bold, lists, tables, code blocks, etc.).
                Match the language of the user's message - if they speak Russian, answer in Russian; if English, answer in English.
                """
                
                finalText = try await openAIService.chat(
                    userMessage: transcription,
                    history: conversationHistory,
                    systemPrompt: systemPrompt,
                    model: gptModel,
                    enableWebSearch: true
                )
                
                conversationHistory.append((role: "user", content: transcription))
                conversationHistory.append((role: "assistant", content: finalText))
                lastProcessedText = finalText
                processingState = .showingResult(finalText)
                
            case .respond:
                // Respond mode - clipboard is the message to respond TO, voice is HOW to respond
                processingState = .processing
                var messageToRespondTo = ""
                if useClipboardContext {
                    switch clipboardContent {
                    case .text(let text): messageToRespondTo = text
                    case .image: messageToRespondTo = "[Image in clipboard]"
                    case .empty: break
                    }
                }
                
                let respondSystemPrompt = """
                You are a response writer. The user shows you a message/email/text they received and tells you how to respond.
                Your task is to WRITE A RESPONSE to that message based on the user's instructions.
                DO NOT answer or analyze the message yourself - write a response that the USER can send.
                Return only the response text, ready to be sent.
                Match the language of the original message unless user specifies otherwise.
                """
                
                let respondUserMessage: String
                if messageToRespondTo.isEmpty {
                    respondUserMessage = "Write a response: \(transcription)"
                } else {
                    respondUserMessage = """
                    MESSAGE TO RESPOND TO:
                    ---
                    \(messageToRespondTo)
                    ---
                    
                    HOW TO RESPOND: \(transcription)
                    
                    Write a response I can send:
                    """
                }
                
                finalText = try await openAIService.chat(
                    userMessage: respondUserMessage,
                    history: [],
                    systemPrompt: respondSystemPrompt,
                    model: gptModel,
                    enableWebSearch: true
                )
                
                logToFile("Respond mode result: \(finalText.prefix(100))")
                lastProcessedText = finalText
                await handleResult(finalText, forMode: currentMode)
                
            case .code:
                // Code mode - generate code from voice description
                processingState = .processing
                let languageHint = codeLanguageMode.promptHint
                let codeSystemPrompt = """
                You are a code generator. Generate code based on the user's voice description.
                You can search the web for API docs or examples if needed.
                \(languageHint)
                Return ONLY the code - no explanations, no markdown code blocks, no comments unless specifically asked.
                """
                
                finalText = try await openAIService.chat(
                    userMessage: "Generate code: \(transcription)",
                    history: [],
                    systemPrompt: codeSystemPrompt,
                    model: gptModel,
                    enableWebSearch: true
                )
                
                logToFile("Code mode result: \(finalText.prefix(100))")
                lastProcessedText = finalText
                await handleResult(finalText, forMode: currentMode)
                
            case .process:
                // Process mode - process clipboard with voice command
                processingState = .processing
                
                switch clipboardContent {
                case .text(let textContent):
                    // Text processing
                    let processSystemPrompt = """
                    You are a text processor. Process the given content according to the user's command.
                    You can search the web for additional context if needed.
                    Return ONLY the processed result - no explanations, no extra text.
                    """
                    
                    let processUserMessage = """
                    CONTENT TO PROCESS:
                    ---
                    \(textContent)
                    ---
                    
                    COMMAND: \(transcription)
                    
                    Processed result:
                    """
                    
                    finalText = try await openAIService.chat(
                        userMessage: processUserMessage,
                        history: [],
                        systemPrompt: processSystemPrompt,
                        model: gptModel,
                        enableWebSearch: true
                    )
                    
                case .image(let imageData):
                    // Image processing with GPT-4 Vision
                    let visionSystemPrompt = """
                    You are an image processor. Analyze the image and follow the user's command.
                    Return ONLY the result - no explanations unless asked.
                    """
                    
                    finalText = try await openAIService.chatWithImage(
                        userMessage: transcription,
                        imageData: imageData,
                        systemPrompt: visionSystemPrompt
                    )
                    
                case .empty:
                    processingState = .error("Clipboard is empty")
                    hideWindowAfterDelay()
                    return
                }
                
                lastProcessedText = finalText
                await handleResult(finalText, forMode: currentMode)
                
            case .transcribe:
                // Normal transcribe mode - fix and paste with selected formatting
                if enableGPTProcessing {
                    processingState = .processing
                    let prompt = formattingMode.prompt + "\nKeep the same language as the original text."
                    finalText = try await openAIService.postProcess(
                        text: transcription,
                        prompt: prompt,
                        model: gptModel
                    )
                }
                
                lastProcessedText = finalText
                await handleResult(finalText, forMode: currentMode)
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            processingState = .error(error.localizedDescription)
            hideWindowAfterDelay()
        }
    }
    
    /// Handle the result based on mode and autoPaste setting
    private func handleResult(_ text: String, forMode mode: RecordingMode) async {
        logToFile("handleResult called: mode=\(mode), autoPaste=\(autoPasteResult), textLen=\(text.count)")
        
        // Ask mode always shows in chat
        if mode == .askGPT {
            processingState = .showingResult(text)
            return
        }
        
        // Other modes: check autoPaste setting
        if autoPasteResult {
            // Paste to active app
            logToFile("handleResult: pasting result, length: \(text.count)")
            
            RecordingWindowController.shared.hideWindow()
            processingState = .idle
            
            if let app = previousApp {
                logToFile("Restoring focus to: \(app.localizedName ?? "unknown")")
                app.activate(options: [.activateIgnoringOtherApps])
            }
            
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {}
            
            pasteService.copyAndPaste(text: text)
            logToFile("copyAndPaste called")
            previousApp = nil
        } else {
            // Show in chat - add to conversation history so it displays
            logToFile("handleResult: showing in chat")
            conversationHistory.append((role: "user", content: lastTranscription))
            conversationHistory.append((role: "assistant", content: text))
            processingState = .showingResult(text)
        }
    }
    
    func cancelRecording() {
        audioRecorder.stopRecording()
        isRecording = false
        processingState = .idle
        recordingMode = .transcribe
        conversationHistory = []
        RecordingWindowController.shared.hideWindow()
        
        if let app = previousApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        previousApp = nil
    }
    
    func dismissResult(copyToClipboard: Bool = false) {
        if copyToClipboard, case .showingResult(let text) = processingState {
            pasteService.copyToClipboard(text: text)
        }
        processingState = .idle
        recordingMode = .transcribe
        conversationHistory = [] // Clear conversation
        RecordingWindowController.shared.hideWindow()
        
        if let app = previousApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
    
    private func hideWindowAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let state = self?.processingState else { return }
            switch state {
            case .recording, .transcribing, .processing, .showingResult:
                break // Don't hide
            case .idle, .error:
                RecordingWindowController.shared.hideWindow()
            }
        }
    }
    
    private func logToFile(_ message: String) {
        let logFile = "/tmp/whisper_appstate.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
        print("AppState: \(message)")
    }
}

