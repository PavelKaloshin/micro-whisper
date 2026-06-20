# Whisper — build tasks
# `make` (or `make build`) produces a Release Whisper.app with code signing
# disabled, mirroring the CI release workflow (.github/workflows/release.yml).

.DEFAULT_GOAL := build
.PHONY: build run clean test spm-path test-integration

PROJECT := Whisper.xcodeproj
SCHEME := Whisper
CONFIG := Release
DERIVED := build
APP := $(DERIVED)/Build/Products/$(CONFIG)/Whisper.app
DEBUG_APP := $(DERIVED)/Build/Products/Debug/Whisper.app

build:
	xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		build

run:
			xcodebuild -project $(PROJECT) \
							-scheme $(SCHEME) \
							-configuration Debug \
							-derivedDataPath $(DERIVED) \
							CODE_SIGN_IDENTITY="-" \
							CODE_SIGNING_REQUIRED=NO \
							CODE_SIGNING_ALLOWED=NO \
							build
			@pkill -f "$(DEBUG_APP)/Contents/MacOS/Whisper" 2>/dev/null || true
			open "$(DEBUG_APP)"

clean:
	rm -rf $(DERIVED)

test:
		xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
				-configuration Debug -derivedDataPath $(DERIVED) \
				-destination 'platform=macOS' \
				CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
test-integration:
	./scripts/run-integration-tests.sh

spm-path:
	@echo $(DERIVED)/SourcePackages/checkouts
