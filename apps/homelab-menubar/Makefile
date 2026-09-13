APP_NAME    := Homelab
BUNDLE      := $(APP_NAME).app
BUILD_DIR   := .build/release
STAGE_DIR   := .build/$(BUNDLE)
INSTALL_DIR := /Applications
CORE_DIR    := ../homelab-core
IOS_DIR     := ../homelab-ios
SIMULATOR   ?= iPhone 17

.PHONY: all test test-core test-menubar build bundle install clean run \
        ios-generate ios-build

all: bundle

# Both packages: the shared core holds the domain, this one holds the macOS
# half. A change to either can break the other, so neither is tested alone.
test: test-core test-menubar

test-core:
	swift test --package-path $(CORE_DIR)

test-menubar:
	swift test

build:
	swift build -c release --product HomelabMenuBar

# SwiftPM emits a bare executable; MenuBarExtra needs a real bundle so that
# LSUIElement is honoured and the app has no Dock icon.
bundle: build
	rm -rf "$(STAGE_DIR)"
	mkdir -p "$(STAGE_DIR)/Contents/MacOS"
	mkdir -p "$(STAGE_DIR)/Contents/Resources"
	cp "$(BUILD_DIR)/HomelabMenuBar" "$(STAGE_DIR)/Contents/MacOS/HomelabMenuBar"
	cp Resources/Info.plist "$(STAGE_DIR)/Contents/Info.plist"
	codesign --force --deep --sign - "$(STAGE_DIR)"
	@echo "Built $(STAGE_DIR)"

install: bundle
	rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	cp -R "$(STAGE_DIR)" "$(INSTALL_DIR)/$(BUNDLE)"
	@echo "Installed $(INSTALL_DIR)/$(BUNDLE)"
	@echo "Launch it with: open '$(INSTALL_DIR)/$(BUNDLE)'"

run: bundle
	open "$(STAGE_DIR)"

# The iOS app is an Xcode project, which SwiftPM cannot produce — the spec is
# checked in and the .xcodeproj is generated, never committed.
#
# There is no `ios-test`: every testable decision lives in HomelabCore and is
# covered by `make test-core`. The iOS target is views and wiring, so a compile
# is what there is to verify here.
ios-generate:
	cd $(IOS_DIR) && xcodegen generate

ios-build: ios-generate
	cd $(IOS_DIR) && xcodebuild build \
		-project Homelab.xcodeproj -scheme Homelab \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)'

clean:
	swift package clean
	swift package --package-path $(CORE_DIR) clean
	rm -rf .build $(CORE_DIR)/.build $(IOS_DIR)/Homelab.xcodeproj
