APP_NAME      := MOP
APP_DISPLAY   := MOP
BUILD_DIR     := .build
APP_BUNDLE    := $(CURDIR)/$(APP_NAME).app
DIST_DIR      := $(CURDIR)/dist
VERSION       ?= $(shell cat VERSION)

# ── Signing ────────────────────────────────────────────────────────────────────
# Set DEVELOPER_ID_APP in your environment or pass on the command line:
#   make bundle DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
DEVELOPER_ID_APP ?=

.PHONY: build run bundle notarize release help

help:
	@echo "Targets:"
	@echo "  build                    swift build (debug)"
	@echo "  run                      build + run"
	@echo "  bundle [VERSION=x.y.z]   release .app → /Applications"
	@echo "  notarize                 bundle + DMG + notarize + staple → dist/"
	@echo "  release                  notarize + sign_update + update appcast → dist/"

build:
	swift build

run: build
	swift run $(APP_NAME)

bundle:
	@echo "=== Super Voice $(VERSION) ==="
	swift build -c release
	@BINARY="$(BUILD_DIR)/release/$(APP_NAME)"; \
	[ -f "$$BINARY" ] || { echo "Error: binary not found at $$BINARY"; exit 1; }; \
	echo "Assembling .app bundle..."; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"; \
	cp "$$BINARY" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	[ -f Sources/AppIcon.icns ] && cp Sources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns" || true; \
	sed 's|{{VERSION}}|$(VERSION)|g' templates/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"; \
	echo "Signing frameworks..."; \
	find "$(APP_BUNDLE)" \( -name '*.dylib' -o -name '*.framework' \) | while read f; do \
		if [ -n "$(DEVELOPER_ID_APP)" ]; then \
			codesign --force --options runtime --timestamp \
				--entitlements MOP.entitlements \
				--sign "$(DEVELOPER_ID_APP)" "$$f"; \
		else \
			codesign --force --sign - "$$f"; \
		fi; \
	done; \
	echo "Signing app bundle..."; \
	if [ -n "$(DEVELOPER_ID_APP)" ]; then \
		codesign --force --options runtime --timestamp \
			--entitlements MOP.entitlements \
			--sign "$(DEVELOPER_ID_APP)" "$(APP_BUNDLE)"; \
	else \
		echo "⚠️  No DEVELOPER_ID_APP — using ad-hoc sign (dev only, Gatekeeper will block)"; \
		codesign --force --sign - "$(APP_BUNDLE)"; \
	fi; \
	echo "Installing to /Applications/$(APP_NAME).app..."; \
	rm -rf "/Applications/$(APP_NAME).app"; \
	cp -R "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"; \
	echo "✅ $(APP_DISPLAY) $(VERSION) installed to /Applications."

notarize: bundle
	@[ -n "$(DEVELOPER_ID_APP)" ] || { echo "Error: DEVELOPER_ID_APP not set"; exit 1; }
	@mkdir -p "$(DIST_DIR)"
	@DMG="$(DIST_DIR)/MOP-$(VERSION).dmg"; \
	ZIP="$(DIST_DIR)/MOP-$(VERSION).zip"; \
	echo "Creating DMG..."; \
	hdiutil create -volname "$(APP_DISPLAY)" -srcfolder "$(APP_BUNDLE)" -ov -format UDZO "$$DMG"; \
	echo "Signing DMG..."; \
	codesign --sign "$(DEVELOPER_ID_APP)" --timestamp "$$DMG"; \
	echo "Submitting to Apple notarization (this takes 1–5 min)..."; \
	xcrun notarytool submit "$$DMG" --keychain-profile "notary" --wait; \
	echo "Stapling ticket to DMG..."; \
	xcrun stapler staple "$$DMG"; \
	echo "Creating ZIP for Sparkle..."; \
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$$ZIP"; \
	echo "Verifying..."; \
	spctl --assess --type open --context context:primary-signature -v "$$DMG"; \
	echo "✅ $(DIST_DIR)/MOP-$(VERSION).{dmg,zip} ready."

release: notarize
	@bash scripts/release.sh "$(VERSION)" "$(DIST_DIR)/MOP-$(VERSION).zip"
