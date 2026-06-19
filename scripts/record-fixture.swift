#!/usr/bin/env swift
//
// record-fixture.swift — record a short audio fixture for the integration tests.
//
// Usage:
//   swift scripts/record-fixture.swift [output-path] [seconds]
//
// Defaults: WhisperTests/Fixtures/hello_en.wav, 5 seconds.
// Writes 24 kHz mono 16-bit PCM WAV (works for both WhisperKit and the
// OpenAI Realtime test). On first run macOS asks your terminal for microphone
// access — allow it (System Settings > Privacy & Security > Microphone).
//
// Suggested phrase: "the quick brown fox jumps over the lazy dog".

import AVFoundation
import Foundation

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "WhisperTests/Fixtures/hello_en.wav"
let duration = args.count > 2 ? (Double(args[2]) ?? 5.0) : 5.0

// 1) Microphone permission (wait for the prompt to be answered).
let sem = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .audio) { ok in granted = ok; sem.signal() }
sem.wait()
guard granted else {
    FileHandle.standardError.write(Data("Microphone permission denied. Enable it for your terminal in System Settings > Privacy & Security > Microphone, then re-run.\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 24000,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false
]

do {
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    guard recorder.prepareToRecord() else {
        FileHandle.standardError.write(Data("Failed to prepare recorder.\n".utf8))
        exit(2)
    }
    // Small countdown so you're ready.
    for n in [3, 2, 1] { print("Recording in \(n)…"); Thread.sleep(forTimeInterval: 1) }
    recorder.record()
    print("● Recording \(Int(duration))s — speak now.")
    Thread.sleep(forTimeInterval: duration)
    recorder.stop()
    print("✓ Saved \(outPath)")
} catch {
    FileHandle.standardError.write(Data("Recording failed: \(error.localizedDescription)\n".utf8))
    exit(2)
}
