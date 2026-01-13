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

enum RecordingMode: String {
    case transcribe = "transcribe"  // Just transcribe and fix
    case askGPT = "askGPT"          // Ask GPT and show answer
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
    @Published var conversationHistory: [(role: String, content: String)] = []
    
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
            // Clear conversation if starting fresh (not from showingResult)
            if recordingMode != .askGPT {
                conversationHistory = []
            }
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
            
            if currentMode == .askGPT {
                // Ask GPT mode - get an answer with conversation history
                processingState = .processing
                let systemPrompt = """
                You are a helpful voice assistant. The user speaks to you via voice, and you answer their questions.
                Answer concisely and helpfully. Use markdown formatting for better readability (bold, lists, tables, code blocks, etc.).
                Match the language of the user's message - if they speak Russian, answer in Russian; if English, answer in English.
                """
                
                finalText = try await openAIService.chat(
                    userMessage: transcription,
                    history: conversationHistory,
                    systemPrompt: systemPrompt,
                    model: gptModel
                )
                
                // Add to conversation history
                conversationHistory.append((role: "user", content: transcription))
                conversationHistory.append((role: "assistant", content: finalText))
                
                lastProcessedText = finalText
                
                // Show result in the overlay
                processingState = .showingResult(finalText)
                // Don't auto-hide, user will dismiss or continue
                
            } else {
                // Normal transcribe mode - fix and paste
                if enableGPTProcessing && !postProcessingPrompt.isEmpty {
                    processingState = .processing
                    finalText = try await openAIService.postProcess(
                        text: transcription,
                        prompt: postProcessingPrompt,
                        model: gptModel
                    )
                }
                
                lastProcessedText = finalText
                
                // Log the flow
                logToFile("Processing complete, finalText length: \(finalText.count)")
                
                // Hide window FIRST
                RecordingWindowController.shared.hideWindow()
                processingState = .idle
                logToFile("Window hidden")
                
                // Restore focus to the previous app
                if let app = previousApp {
                    logToFile("Restoring focus to: \(app.localizedName ?? "unknown")")
                    app.activate(options: [.activateIgnoringOtherApps])
                } else {
                    logToFile("No previous app to restore focus to")
                }
                
                // Wait for focus to be restored
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                logToFile("After delay, about to paste")
                
                // Copy to clipboard and paste
                pasteService.copyAndPaste(text: finalText)
                logToFile("copyAndPaste called")
            }
            
            // Clean up
            previousApp = nil
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            processingState = .error(error.localizedDescription)
            hideWindowAfterDelay()
        }
    }
    
    func cancelRecording() {
        audioRecorder.stopRecording()
        isRecording = false
        processingState = .idle
        recordingMode = .transcribe
        conversationHistory = [] // Clear conversation
        RecordingWindowController.shared.hideWindow()
        
        if let app = previousApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }
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

