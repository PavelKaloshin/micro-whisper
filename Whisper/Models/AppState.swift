import Foundation
import SwiftUI

enum ProcessingState: Equatable {
    case idle
    case recording
    case transcribing
    case processing
    case error(String)
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var processingState: ProcessingState = .idle
    @Published var lastTranscription: String = ""
    @Published var lastProcessedText: String = ""
    
    // MARK: - Settings
    @AppStorage("gptModel") var gptModel: String = "gpt-4o-mini"
    @AppStorage("postProcessingPrompt") var postProcessingPrompt: String = "Fix grammar, punctuation, and formatting. Keep the original meaning and style. Return only the corrected text without explanations."
    @AppStorage("enableGPTProcessing") var enableGPTProcessing: Bool = true
    
    // MARK: - Services
    private let audioRecorder = AudioRecorder()
    private let openAIService = OpenAIService()
    private let pasteService = PasteService()
    
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
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    // MARK: - Recording Controls
    func startRecording() {
        guard hasAPIKey else {
            processingState = .error("No API key configured")
            return
        }
        
        do {
            try audioRecorder.startRecording()
            isRecording = true
            processingState = .recording
        } catch {
            processingState = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecordingAndProcess() async {
        isRecording = false
        
        guard let audioURL = audioRecorder.stopRecording() else {
            processingState = .error("No audio recorded")
            return
        }
        
        // Transcribe with Whisper
        processingState = .transcribing
        do {
            let transcription = try await openAIService.transcribe(audioURL: audioURL)
            lastTranscription = transcription
            
            var finalText = transcription
            
            // Post-process with GPT if enabled
            if enableGPTProcessing && !postProcessingPrompt.isEmpty {
                processingState = .processing
                finalText = try await openAIService.postProcess(
                    text: transcription,
                    prompt: postProcessingPrompt,
                    model: gptModel
                )
            }
            
            lastProcessedText = finalText
            
            // Copy to clipboard and paste
            pasteService.copyAndPaste(text: finalText)
            
            processingState = .idle
            
            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            processingState = .error(error.localizedDescription)
        }
    }
    
    func cancelRecording() {
        audioRecorder.stopRecording()
        isRecording = false
        processingState = .idle
    }
}

