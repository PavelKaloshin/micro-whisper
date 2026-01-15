# Whisper

A native macOS menu bar app for voice transcription using OpenAI's Whisper API with GPT post-processing. Press a hotkey to record your voice, and the transcribed (and optionally refined) text is automatically pasted into your current text field.

## Features

- **Global Hotkey**: Double-press Globe key or `Cmd + Shift + 9` to start/stop recording
- **Whisper Transcription**: High-quality speech-to-text via OpenAI's Whisper API
- **GPT Post-Processing**: Automatically fix grammar, punctuation, and formatting
- **Multiple Modes**: Transcribe, Ask GPT, Respond, Code generation, Process clipboard
- **Formatting Options**: Default, Notion-style, Slack-style output
- **Custom Terminology**: Add domain-specific terms for better transcription accuracy
- **Web Search**: GPT can search the web for current information
- **Auto-Paste**: Results are copied to clipboard and pasted into the active text field
- **Menu Bar App**: Runs quietly in the background with minimal footprint

## Requirements

- macOS 14.0 (Sonoma) or later
- OpenAI API key

## Installation

### Download Release (Recommended)

1. Go to [Releases](https://github.com/IncodeTechnologies/whisper/releases)
2. Download the latest `Whisper-X.X.X.dmg` or `Whisper-X.X.X.zip`
3. **For DMG**: Open the DMG and drag Whisper to Applications folder
4. **For ZIP**: Extract and move `Whisper.app` to Applications folder
5. **Remove quarantine** (required for unsigned apps):
   ```bash
   xattr -cr /Applications/Whisper.app
   ```
6. Launch the app

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/IncodeTechnologies/whisper.git
   cd whisper
   ```

2. Build with Xcode:
   ```bash
   xcodebuild -project Whisper.xcodeproj -scheme Whisper -configuration Release build
   ```
   
   Or open in Xcode and press `Cmd + R`

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

1. **Start Recording**: Double-press 🌐 Globe key or `Cmd + Shift + 9`
2. **Select Mode**: Use hotkeys to switch modes (T/A/R/C/P)
3. **Speak**: Recording indicator shows audio level
4. **Stop Recording**: Press the hotkey again or Escape to cancel
5. **Done**: Result is pasted or shown in chat depending on settings

### Recording Hotkeys

| Key | Action |
|-----|--------|
| 🌐🌐 | Start/stop recording (double Globe) |
| ⌘⇧9 | Start/stop recording (alternative) |
| Esc / Q | Cancel recording |

### Mode Selection (during recording)

| Key | Mode | Description |
|-----|------|-------------|
| T | Transcribe | Convert speech to text with formatting |
| A | Ask GPT | Ask a question, get an answer in chat |
| R | Respond | Use clipboard as context, voice as instruction |
| C | Code | Generate code from voice description |
| P | Process | Process clipboard content with voice command |

### Language Selection

| Key | Language |
|-----|----------|
| 0 | Auto-detect |
| 1 | English |
| 2 | Russian |

### Format Selection (Transcribe mode)

| Key | Format |
|-----|--------|
| D | Default |
| N | Notion-style |
| S | Slack-style |

### Other Options

| Key | Option |
|-----|--------|
| O | Toggle Paste/Chat output |
| V | Toggle clipboard context |
| X | Toggle terminology correction |

## Settings

Access via menu bar icon → Settings:

- **General**: Language, GPT model, post-processing prompt
- **Terms**: Custom terminology for better transcription
- **API**: OpenAI API key configuration
- **Permissions**: Microphone and Accessibility status

## Permissions Explained

| Permission | Purpose |
|------------|---------|
| Microphone | Record audio for transcription |
| Accessibility | Simulate paste into active app |
| Automation | More reliable paste via System Events |

## License

MIT License - see [LICENSE](LICENSE) for details.

