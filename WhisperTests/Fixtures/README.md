# Test audio fixtures

Drop short recorded audio clips here to enable the opt-in integration tests
(Layers 3 & 4). They are read by path at test time (not bundled), so any audio
format `AVAudioFile` can open works (`.wav` / `.m4a`, mono, 16–24 kHz is ideal).

## Expected files

| File | Used by | Suggested content |
|------|---------|-------------------|
| `hello_en.wav` | `WhisperKitFixtureTests`, `RealtimeIntegrationTests`, `OpenAIServiceIntegrationTests` | ~3–5 s, English, a clear known phrase (e.g. "the quick brown fox jumps over the lazy dog"). |

Add more (e.g. `hello_ru.wav`) and a matching test as needed. After recording,
tighten the assertions in the test to check for the actual spoken words.

## Running the integration tests

Use `make test-integration` (wraps `scripts/run-integration-tests.sh`). It always
sets the opt-in flags and runs every layer:

```bash
# WhisperKit on-device (downloads the `base` model on first run) — no key needed.
# Realtime (cloud) and the classic OpenAI REST path (Whisper transcription +
# chat-completions post-processing) too — read OPENAI_API_KEY from your shell env:
OPENAI_API_KEY=sk-... make test-integration

# Without a key the WhisperKit layer still passes; the Realtime and OpenAI REST
# layers skip/fail on the missing key, so export the key to exercise everything.
```

Gates: `RUN_WHISPERKIT_TESTS` (on-device, no key), `RUN_REALTIME_TESTS` (cloud
realtime), `RUN_OPENAI_TESTS` (classic REST: `OpenAIServiceIntegrationTests`).

> Why a wrapper and not `RUN_REALTIME_TESTS=1 … make test`? The macOS XCTest host
> only reads environment variables declared in the *scheme's* env block — it does
> NOT inherit your shell environment. The script injects the gate flags and the key
> into a throwaway scheme under `xcuserdata/` (gitignored, so the key can never be
> committed) and deletes it on exit, so the key never lands in argv or any log.

`make test` (the default) skips both layers and stays fast/offline.

> Do not commit anything sensitive. Plain spoken test phrases are fine; don't
> record private content.
