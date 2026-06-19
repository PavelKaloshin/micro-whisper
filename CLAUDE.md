# CLAUDE.md

Guidance for Claude Code working in this repository.

## Building — always use the Makefile

**Build with `make`, not raw `xcodebuild`.** The `make` command is pre-approved in
`.claude/settings.json`, so it runs without a permission prompt; a bare `xcodebuild …`
invocation is not allow-listed and will ask for approval every time.

```bash
make            # or `make build` — Release build, code signing disabled (compile check)
make run        # build, then launch Whisper.app
make test       # run the unit + integration test suite (xcodebuild test, macOS)
make clean      # remove the build/ directory
```

The `Makefile` is the single source of truth for the build command (it mirrors the CI
release workflow). Do not hand-roll `xcodebuild` invocations. Note: editing the
`Makefile` is denied in `.claude/settings.json` — change build flags by asking the user.

## Project notes

- macOS menu-bar app (Swift 5, SwiftUI + AppKit). Single Xcode target `Whisper`.
- Dependencies (Swift Package Manager): `HotKey`, `WhisperKit` (argmax-oss-swift).
- No test target yet — being added.
