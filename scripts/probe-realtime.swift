#!/usr/bin/env swift
//
// probe-realtime.swift — diagnostic harness for the OpenAI Realtime transcription
// path used by OpenAIRealtimeLiveTranscriber. Streams a fixture WAV over the
// WebSocket and logs EVERY server frame plus the close/error reason, so we can see
// why a transcript does (or doesn't) come back. Standalone (no @testable import),
// so it inherits the shell environment directly.
//
// Usage:
//   OPENAI_API_KEY=sk-… swift scripts/probe-realtime.swift [fixture.wav] [chunkMillis]
//
// Defaults: WhisperTests/Fixtures/hello_en.wav, chunk = 0 (single append, mirrors
// the current app). Pass e.g. 100 to chunk audio into 100 ms appends.

import AVFoundation
import Foundation

let args = CommandLine.arguments
let fixture = args.count > 1 ? args[1] : "WhisperTests/Fixtures/hello_en.wav"
let chunkMillis = args.count > 2 ? (Int(args[2]) ?? 0) : 0
let model = ProcessInfo.processInfo.environment["REALTIME_MODEL"] ?? "gpt-4o-transcribe"

guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
    FileHandle.standardError.write(Data("OPENAI_API_KEY not set in environment.\n".utf8))
    exit(1)
}

func log(_ s: String) { print(s); fflush(stdout) }

// MARK: - Convert fixture to 24 kHz mono PCM16 little-endian bytes.

let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true
)!

func pcm16Bytes(_ url: URL) throws -> Data {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    log("fixture: \(url.lastPathComponent)  src=\(Int(format.sampleRate))Hz ch=\(format.channelCount) frames=\(file.length)")
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "alloc read buffer"])
    }
    try file.read(into: inBuf)
    guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
        throw NSError(domain: "probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "create converter"])
    }
    let ratio = targetFormat.sampleRate / format.sampleRate
    let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1
    guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else {
        throw NSError(domain: "probe", code: 3, userInfo: [NSLocalizedDescriptionKey: "alloc out buffer"])
    }
    var consumed = false
    var convError: NSError?
    converter.convert(to: out, error: &convError) { _, status in
        if consumed { status.pointee = .noDataNow; return nil }
        consumed = true; status.pointee = .haveData; return inBuf
    }
    if let convError { throw convError }
    guard let ch = out.int16ChannelData, out.frameLength > 0 else {
        throw NSError(domain: "probe", code: 4, userInfo: [NSLocalizedDescriptionKey: "empty conversion"])
    }
    let bytes = Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    log("converted: 24000Hz mono pcm16  \(bytes.count) bytes (\(out.frameLength) frames)")
    return bytes
}

// MARK: - WebSocket plumbing

final class Probe: NSObject, URLSessionWebSocketDelegate {
    var ws: URLSessionWebSocketTask!
    let done = DispatchSemaphore(value: 0)
    var transcriptDeltas = ""
    var sawCompleted = false

    func send(_ object: [String: Any], label: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return }
        let preview = object["type"] as? String ?? "?"
        let size = object["audio"] != nil ? " (\(s.count) chars)" : ""
        log("→ send \(preview)\(size)  [\(label)]")
        ws.send(.string(s)) { err in
            if let err { log("   send error: \(err.localizedDescription)") }
        }
    }

    func receive() {
        ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                log("✗ receive failure: \(error.localizedDescription)")
                self.done.signal()
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receive()
            }
        }
    }

    func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { log("← (unparseable) \(text.prefix(200))"); return }
        switch type {
        case "conversation.item.input_audio_transcription.delta":
            let d = obj["delta"] as? String ?? ""
            transcriptDeltas += d
            log("← delta: \(d)")
        case "conversation.item.input_audio_transcription.completed":
            sawCompleted = true
            log("← COMPLETED transcript: \(obj["transcript"] as? String ?? "<none>")")
        case "error":
            let e = obj["error"] as? [String: Any]
            log("← ERROR: \(e?["message"] as? String ?? text)")
        default:
            log("← \(type)")
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        log("● websocket OPEN")
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let r = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        log("● websocket CLOSED code=\(closeCode.rawValue) reason=\(r)")
        done.signal()
    }
}

let pcm = try pcm16Bytes(URL(fileURLWithPath: fixture))

let probe = Probe()
let session = URLSession(configuration: .default, delegate: probe, delegateQueue: nil)
var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
// GA Realtime API: no OpenAI-Beta header.
probe.ws = session.webSocketTask(with: request)
probe.receive()
probe.ws.resume()

// Give the socket a moment to open, then configure + stream.
Thread.sleep(forTimeInterval: 1.0)

probe.send([
    "type": "session.update",
    "session": [
        "type": "transcription",
        "audio": [
            "input": [
                "format": ["type": "audio/pcm", "rate": 24000],
                "transcription": ["model": model]
            ]
        ]
    ]
], label: "session.update model=\(model)")

Thread.sleep(forTimeInterval: 0.5)

if chunkMillis <= 0 {
    probe.send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()],
               label: "single append")
} else {
    let bytesPerChunk = (24000 * 2 * chunkMillis) / 1000   // 24kHz * 2 bytes * ms
    var offset = 0, n = 0
    while offset < pcm.count {
        let end = min(offset + bytesPerChunk, pcm.count)
        let slice = pcm.subdata(in: offset..<end)
        probe.send(["type": "input_audio_buffer.append", "audio": slice.base64EncodedString()],
                   label: "chunk \(n) [\(slice.count)B]")
        offset = end; n += 1
        Thread.sleep(forTimeInterval: 0.02)
    }
}

probe.send(["type": "input_audio_buffer.commit"], label: "commit")

// Wait up to 15s for transcription events or a close.
log("… waiting up to 15s for events")
_ = probe.done.wait(timeout: .now() + 15)
log("=== RESULT: completed=\(probe.sawCompleted)  deltas=\"\(probe.transcriptDeltas)\"")
