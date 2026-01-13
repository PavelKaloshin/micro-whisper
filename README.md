# Whisper

A native macOS menu bar app for voice transcription using OpenAI's Whisper API with GPT post-processing. Press a hotkey to record your voice, and the transcribed (and optionally refined) text is automatically pasted into your current text field.

## Features

- **Global Hotkey**: Start/stop recording from anywhere with `Cmd + Shift + 9`
- **Whisper Transcription**: High-quality speech-to-text via OpenAI's Whisper API
- **GPT Post-Processing**: Automatically fix grammar, punctuation, and formatting
- **Auto-Paste**: Results are copied to clipboard and pasted into the active text field
- **Menu Bar App**: Runs quietly in the background with minimal footprint
- **Configurable**: Custom hotkey, GPT prompt, and model selection

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)
- OpenAI API key

## Installation

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/whisper.git
   cd whisper
   ```

2. Open the Xcode project:
   ```bash
   open Whisper.xcodeproj
   ```

3. Build and run:
   - Select your Mac as the target device
   - Press `Cmd + R` to build and run

### First-Time Setup

1. **Grant Permissions**:
   - **Microphone**: Required for audio recording. macOS will prompt you on first recording attempt.
   - **Accessibility**: Required for auto-paste functionality. Go to `System Settings > Privacy & Security > Accessibility` and enable Whisper.

2. **Configure API Key**:
   - Click the Whisper icon in the menu bar
   - Select "Settings..."
   - Enter your OpenAI API key
   - (Optional) Customize the GPT post-processing prompt

## Usage

1. **Start Recording**: Press `Cmd + Shift + 9` (or your configured hotkey)
2. **Speak**: The menu bar icon will show a red indicator while recording
3. **Stop Recording**: Press the hotkey again
4. **Wait**: Your speech is transcribed and processed
5. **Done**: The result is automatically pasted into your current text field

### Settings

Access settings via the menu bar icon:

- **OpenAI API Key**: Your API key for Whisper and GPT
- **GPT Model**: Choose between `gpt-4o` and `gpt-4o-mini`
- **Post-Processing Prompt**: Customize how GPT refines your transcription
- **Enable GPT Processing**: Toggle post-processing on/off

## Permissions Explained

| Permission | Purpose |
|------------|---------|
| Microphone | Record audio for transcription |
| Accessibility | Simulate `Cmd+V` to paste text into active app |

## License

MIT License - see [LICENSE](LICENSE) for details.

