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

## Command permissions (avoid fighting the prompts)

To keep the approval surface small and safe, `.claude/settings.json` pre-allows
only safe, repetitive commands — take the trusted path instead of the raw one:

- **Build / test:** use `make` (`make build`, `make test`, `make run`, `make clean`).
  Direct `xcodebuild …` is intentionally *not* auto-approved; the `Makefile` is the
  trusted surface (and is write-denied so it can't be silently widened).
- **Allowed read-only:** `grep`, `ls`, `cat`, `plutil -lint`, and read-only git
  (`status`, `diff`, `log`, `show`, `branch`, `rev-parse`).
- **Intentionally still prompting (don't try to route around them):** `find`
  (can `-exec`), `awk` (can `system()`), `sed -i`, `xargs`, `perl -i`, `rm`, raw
  `bash`/`python`/`node`, `curl`/`wget`. Prefer `grep` over `find`/`awk` for search.

When you add a `Makefile` target or wrapper, ask the user to lift the Makefile
write-deny for that one edit, then restore it.

## Project notes

- macOS menu-bar app (Swift 5, SwiftUI + AppKit). Single Xcode target `Whisper`.
- Dependencies (Swift Package Manager): `HotKey`, `WhisperKit` (argmax-oss-swift).
- No test target yet — being added.
