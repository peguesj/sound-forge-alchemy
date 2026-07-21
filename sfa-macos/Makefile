# Sound Forge Alchemy — macOS Native App Build System
# Requires: Xcode 15+, macOS 14 SDK
# Usage: make [build|release|package-local|archive|export|verify-package|clean|open]

SCHEME        := SoundForgeAlchemy
PROJECT       := SoundForgeAlchemy.xcodeproj
WORKSPACE_DIR := $(shell pwd)
BUILD_DIR     := $(WORKSPACE_DIR)/build
ARCHIVE_PATH  := $(BUILD_DIR)/SoundForgeAlchemy.xcarchive
EXPORT_PATH   := $(BUILD_DIR)/export
LOCAL_PACKAGE_DIR := $(BUILD_DIR)/LocalPackage
LOCAL_APP     := $(LOCAL_PACKAGE_DIR)/Sound Forge Alchemy.app
EXPORT_OPTIONS := ExportOptions.plist

# SDK and deployment target
SDK           := macosx
DEPLOYMENT    := 14.0
LOCAL_ARCH    := arm64
SIGN_IDENTITY ?= -
DESTINATION   := platform=macOS,arch=$(LOCAL_ARCH)
ARCHIVE_DESTINATION := generic/platform=macOS

# Derived data goes into build/ to keep repo clean
DERIVED_DATA  := $(BUILD_DIR)/DerivedData

.PHONY: all build release package-local archive export verify-package clean open help

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
		-destination "$(DESTINATION)" \
		-destination-timeout 5 \
		MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-derivedDataPath "$(DERIVED_DATA)" \
		SYMROOT="$(BUILD_DIR)/Debug" \
		build \
		| xcpretty || xcodebuild \
			-project "$(PROJECT)" \
			-scheme "$(SCHEME)" \
			-configuration Debug \
			-sdk $(SDK) \
			-destination "$(DESTINATION)" \
			-destination-timeout 5 \
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
		-destination "$(DESTINATION)" \
		-destination-timeout 5 \
		MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-derivedDataPath "$(DERIVED_DATA)" \
		SYMROOT="$(BUILD_DIR)/Release" \
		build \
		| xcpretty || xcodebuild \
			-project "$(PROJECT)" \
			-scheme "$(SCHEME)" \
			-configuration Release \
			-sdk $(SDK) \
			-destination "$(DESTINATION)" \
			-destination-timeout 5 \
			MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
			-derivedDataPath "$(DERIVED_DATA)" \
			SYMROOT="$(BUILD_DIR)/Release" \
			build
	@echo "==> Release build complete: $(BUILD_DIR)/Release/"

## package-local — Build a local signed .app and verify its code signature
package-local: verify-package
	@BUILD_DIR="$(LOCAL_PACKAGE_DIR)" LOCAL_ARCH="$(LOCAL_ARCH)" DEPLOYMENT_TARGET="$(DEPLOYMENT)" SIGN_IDENTITY="$(SIGN_IDENTITY)" ci/package_local_app.sh
	codesign --verify --deep --strict --verbose=2 "$(LOCAL_APP)"
	@echo "==> Local signed package verified: $(LOCAL_APP)"

## archive — Create .xcarchive for distribution / notarisation
archive:
	@echo "==> Archiving $(SCHEME)…"
	@mkdir -p "$(BUILD_DIR)"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-sdk $(SDK) \
		-destination "$(ARCHIVE_DESTINATION)" \
		MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT) \
		-archivePath "$(ARCHIVE_PATH)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		archive
	@echo "==> Archive complete: $(ARCHIVE_PATH)"

## export — Export .app from archive (requires ExportOptions.plist)
export: archive
	@echo "==> Exporting .app from archive…"
	@mkdir -p "$(EXPORT_PATH)"
	xcodebuild \
		-exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath "$(EXPORT_PATH)" \
		-exportOptionsPlist "$(EXPORT_OPTIONS)"
	@echo "==> Export complete: $(EXPORT_PATH)/Sound Forge Alchemy.app"

## verify-package — Validate packaging/signing/notarization readiness inputs
verify-package:
	@ci/verify_package_readiness.sh

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
	@echo "  LOCAL_ARCH     Local build arch    (default: $(LOCAL_ARCH))"
	@echo "  SIGN_IDENTITY  Local signing ID    (default: ad-hoc '-')"
	@echo "  DESTINATION    Build destination   (default: $(DESTINATION))"
	@echo ""
