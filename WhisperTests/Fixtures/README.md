# Test audio fixtures

Drop short recorded audio clips here to enable the opt-in integration tests
(Layers 3 & 4). They are read by path at test time (not bundled), so any audio
format `AVAudioFile` can open works (`.wav` / `.m4a`, mono, 16–24 kHz is ideal).

## Expected files

| File | Used by | Suggested content |
|------|---------|-------------------|
| `hello_en.wav` | `WhisperKitFixtureTests`, `RealtimeIntegrationTests` | ~3–5 s, English, a clear known phrase (e.g. "the quick brown fox jumps over the lazy dog"). |

Add more (e.g. `hello_ru.wav`) and a matching test as needed. After recording,
tighten the assertions in the test to check for the actual spoken words.

## Running the integration tests

`make test-integration` sets the opt-in flags itself, so:

```bash
# On-device WhisperKit fixture test (downloads the `base` model on first run):
make test-integration

# …and the Realtime (cloud) end-to-end test too — just add the key:
OPENAI_API_KEY=sk-... make test-integration
```

`make test` (the default) skips both layers and stays fast/offline.

> Do not commit anything sensitive. Plain spoken test phrases are fine; don't
> record private content.
