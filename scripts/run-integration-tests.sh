#!/usr/bin/env bash
#
# run-integration-tests.sh — run the opt-in integration tests (WhisperKit on-device
# + OpenAI Realtime) against the recorded fixtures.
#
# The macOS XCTest host only sees environment variables declared in the *scheme's*
# env block — it does NOT inherit the shell environment, and scheme values are taken
# literally (no $(VAR) expansion). So we can't just `RUN_*=1 OPENAI_API_KEY=… make
# test`. Instead we generate a throwaway scheme under xcuserdata/ (which is
# .gitignored, so the injected key can never be committed), inject the gate flags and
# the key read from the environment, run xcodebuild against it, and delete it on exit.
#
# Usage:
#   OPENAI_API_KEY=sk-…  ./scripts/run-integration-tests.sh [extra xcodebuild args]
#
# Examples:
#   ./scripts/run-integration-tests.sh
#   ./scripts/run-integration-tests.sh -only-testing:WhisperTests/RealtimeIntegrationTests
#
# RUN_WHISPERKIT_TESTS requires no key; the Realtime and OpenAI REST tests
# (RUN_REALTIME_TESTS / RUN_OPENAI_TESTS) require OPENAI_API_KEY.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJ="Whisper.xcodeproj"
SHARED_SCHEME="$PROJ/xcshareddata/xcschemes/Whisper.xcscheme"

if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "warning: OPENAI_API_KEY not set — the Realtime test will fail; WhisperKit will still run." >&2
fi

# xcuserdata is gitignored — a safe home for a scheme carrying the key.
USER_DATA_DIR=$(ls -d "$PROJ"/xcuserdata/*.xcuserdatad 2>/dev/null | head -1 || true)
[ -n "$USER_DATA_DIR" ] || USER_DATA_DIR="$PROJ/xcuserdata/$(id -un).xcuserdatad"
SCHEME_DIR="$USER_DATA_DIR/xcschemes"
TMP_SCHEME="$SCHEME_DIR/WhisperIntegration.xcscheme"
mkdir -p "$SCHEME_DIR"

cleanup() { rm -f "$TMP_SCHEME"; }
trap cleanup EXIT

# Build the integration scheme from the shared one: force the Test action to use its
# own env, and inject the gate flags + the key (read from os.environ, never argv).
SRC="$SHARED_SCHEME" DST="$TMP_SCHEME" python3 - <<'PY'
import os, re, html
src, dst = os.environ["SRC"], os.environ["DST"]
s = open(src).read()
s = s.replace('shouldUseLaunchSchemeArgsEnv = "YES"',
              'shouldUseLaunchSchemeArgsEnv = "NO"')
key = html.escape(os.environ.get("OPENAI_API_KEY", ""), quote=True)
block = '''      <EnvironmentVariables>
         <EnvironmentVariable key = "RUN_WHISPERKIT_TESTS" value = "1" isEnabled = "YES"></EnvironmentVariable>
         <EnvironmentVariable key = "RUN_REALTIME_TESTS" value = "1" isEnabled = "YES"></EnvironmentVariable>
         <EnvironmentVariable key = "RUN_OPENAI_TESTS" value = "1" isEnabled = "YES"></EnvironmentVariable>
         <EnvironmentVariable key = "OPENAI_API_KEY" value = "%s" isEnabled = "YES"></EnvironmentVariable>
      </EnvironmentVariables>
''' % key
# Insert the env block immediately after the opening <TestAction …> tag.
s, n = re.subn(r'(<TestAction\b[^>]*>\n)', r'\1' + block, s, count=1)
assert n == 1, "could not find <TestAction> to inject env block"
open(dst, "w").write(s)
PY

echo "▶ running integration tests via scheme WhisperIntegration (key injected, not logged)"
xcodebuild test -project "$PROJ" -scheme WhisperIntegration \
    -configuration Debug -derivedDataPath build -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO "$@"
