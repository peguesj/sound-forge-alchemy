# Sound Forge Alchemy — macOS Native App Build System
# Requires: Xcode 15+, macOS 14 SDK
# Usage: make [build|release|archive|clean|open]

SCHEME        := SoundForgeAlchemy
PROJECT       := SoundForgeAlchemy.xcodeproj
WORKSPACE_DIR := $(shell pwd)
BUILD_DIR     := $(WORKSPACE_DIR)/build
ARCHIVE_PATH  := $(BUILD_DIR)/SoundForgeAlchemy.xcarchive
EXPORT_PATH   := $(BUILD_DIR)/export

# SDK and deployment target
SDK           := macosx
DEPLOYMENT    := 14.0

# Derived data goes into build/ to keep repo clean
DERIVED_DATA  := $(BUILD_DIR)/DerivedData

.PHONY: all build release archive export clean open help

all: build

## build — Compile debug build (fast, no optimisation)
build:
	@echo "==> Building $(SCHEME) (Debug)…"
	@mkdir -p "$(BUILD_DIR)/Debug"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-sdk $(SDK) \
		MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-derivedDataPath "$(DERIVED_DATA)" \
		SYMROOT="$(BUILD_DIR)/Debug" \
		build \
		| xcpretty || xcodebuild \
			-project "$(PROJECT)" \
			-scheme "$(SCHEME)" \
			-configuration Debug \
			-sdk $(SDK) \
			MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
			-derivedDataPath "$(DERIVED_DATA)" \
			SYMROOT="$(BUILD_DIR)/Debug" \
			build
	@echo "==> Debug build complete: $(BUILD_DIR)/Debug/"

## release — Compile optimised release build
release:
	@echo "==> Building $(SCHEME) (Release)…"
	@mkdir -p "$(BUILD_DIR)/Release"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-sdk $(SDK) \
		MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-derivedDataPath "$(DERIVED_DATA)" \
		SYMROOT="$(BUILD_DIR)/Release" \
		build \
		| xcpretty || xcodebuild \
			-project "$(PROJECT)" \
			-scheme "$(SCHEME)" \
			-configuration Release \
			-sdk $(SDK) \
			MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
			-derivedDataPath "$(DERIVED_DATA)" \
			SYMROOT="$(BUILD_DIR)/Release" \
			build
	@echo "==> Release build complete: $(BUILD_DIR)/Release/"

## archive — Create .xcarchive for distribution / notarisation
archive:
	@echo "==> Archiving $(SCHEME)…"
	@mkdir -p "$(BUILD_DIR)"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-sdk $(SDK) \
		MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-archivePath "$(ARCHIVE_PATH)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		archive
	@echo "==> Archive complete: $(ARCHIVE_PATH)"

## export — Export .app from archive (requires ExportOptions.plist)
export: archive
	@echo "==> Exporting .app from archive…"
	@mkdir -p "$(EXPORT_PATH)"
	@if [ ! -f ExportOptions.plist ]; then \
		echo "Creating default ExportOptions.plist for direct distribution…"; \
		/usr/libexec/PlistBuddy -c "Add :method string developer-id" \
			-c "Add :teamID string ''" \
			-c "Add :signingStyle string automatic" \
			-c "Add :stripSwiftSymbols bool true" \
			ExportOptions.plist; \
	fi
	xcodebuild \
		-exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath "$(EXPORT_PATH)" \
		-exportOptionsPlist ExportOptions.plist
	@echo "==> Export complete: $(EXPORT_PATH)/Sound Forge Alchemy.app"

## clean — Remove build artefacts
clean:
	@echo "==> Cleaning build artefacts…"
	@rm -rf "$(BUILD_DIR)"
	@echo "==> Clean complete."

## open — Open project in Xcode
open:
	@echo "==> Opening $(PROJECT) in Xcode…"
	open "$(PROJECT)"

## help — Show available targets
help:
	@echo ""
	@echo "Sound Forge Alchemy — macOS Build Targets"
	@echo "==========================================="
	@grep -E '^## ' Makefile | sed 's/## /  make /' | column -t -s '—'
	@echo ""
	@echo "Environment variables:"
	@echo "  SCHEME         Xcode scheme to build (default: $(SCHEME))"
	@echo "  BUILD_DIR      Output directory    (default: ./build)"
	@echo "  DEPLOYMENT     Min macOS version   (default: $(DEPLOYMENT))"
	@echo ""
