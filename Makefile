APP_NAME      := MOP
APP_DISPLAY   := MOP
BUILD_DIR     := .build
APP_BUNDLE    := $(CURDIR)/$(APP_NAME).app
DIST_DIR      := $(CURDIR)/dist
VERSION       ?= $(shell git tag --sort=-v:refname | head -1 | sed 's/^v//')

-include .env
export

# ── Signing ────────────────────────────────────────────────────────────────────
DEVELOPER_ID_APP ?= Developer ID Application: Desmond Yong Ndifon (KNRDLVLF55)
HARDENED ?= 1
# Sparkle EdDSA public key. Auto-resolved from Keychain if generate_keys is available.
SPARKLE_BIN     := .build/artifacts/sparkle/Sparkle/bin
SPARKLE_PUBLIC_KEY ?= $(shell "$(SPARKLE_BIN)/generate_keys" -p 2>/dev/null || true)

.PHONY: build run bundle notarize release upload help publish _publish _publish_dev major minor fix

help:
	@echo "Targets:"
	@echo "  build                    swift build (debug)"
	@echo "  run                      build + run"
	@echo "  bundle [VERSION=x.y.z]   release .app → /Applications"
	@echo "  notarize                 bundle + DMG + notarize + staple → dist/"
	@echo "  release                  notarize + upload artifacts/appcast to R2"
	@echo "  upload [VERSION=x.y.z]   upload existing dist artifacts to R2"
	@echo "  publish [TYPE=major|minor|fix]   bump version + build + upload to R2"

build:
	swift build

run: build
	swift run $(APP_NAME)

bundle:
	@echo "=== MOP $(VERSION) ==="
	swift build -c release
	@set -eu; \
	BUILD_REL="$$(swift build -c release --show-bin-path)"; \
	BINARY="$$BUILD_REL/$(APP_NAME)"; \
	[ -f "$$BINARY" ] || { echo "Error: binary not found at $$BINARY"; exit 1; }; \
	echo "Assembling .app bundle..."; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"; \
	cp "$$BINARY" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	APP_BINARY="$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	if ! otool -l "$$APP_BINARY" | grep -q '@loader_path/../Frameworks'; then \
		install_name_tool -add_rpath "@loader_path/../Frameworks" "$$APP_BINARY"; \
	fi; \
	[ -f Sources/AppIcon.icns ] || { echo "Error: required resource missing: Sources/AppIcon.icns"; exit 1; }; \
	cp Sources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"; \
	sed -e 's|{{VERSION}}|$(VERSION)|g' \
	    -e 's|{{SPARKLE_PUBLIC_KEY}}|$(SPARKLE_PUBLIC_KEY)|g' \
	    -e "s|{{YEAR}}|$$(date +%Y)|g" \
	    templates/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"; \
	echo "Copying frameworks and resource bundles..."; \
	mkdir -p "$(APP_BUNDLE)/Contents/Frameworks"; \
	[ -d "$$BUILD_REL/Sparkle.framework" ] || { echo "Error: required framework missing: $$BUILD_REL/Sparkle.framework"; exit 1; }; \
	cp -R "$$BUILD_REL/Sparkle.framework" "$(APP_BUNDLE)/Contents/Frameworks/"; \
	for b in "$$BUILD_REL"/*.bundle; do \
		[ -e "$$b" ] && cp -R "$$b" "$(APP_BUNDLE)/Contents/Resources/" || true; \
	done; \
	SPK_FW="$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B"; \
	[ -f "$$SPK_FW/Sparkle" ] || { echo "Error: Sparkle framework binary missing: $$SPK_FW/Sparkle"; exit 1; }; \
	echo "Signing frameworks..."; \
	for f in \
		"$$SPK_FW/XPCServices/org.sparkle-project.InstallerConnection.xpc" \
		"$$SPK_FW/XPCServices/org.sparkle-project.InstallerLauncher.xpc" \
		"$$SPK_FW/XPCServices/org.sparkle-project.InstallerStatus.xpc" \
		"$$SPK_FW/Updater.app" \
		"$$SPK_FW/Autoupdate" \
		"$$SPK_FW/Sparkle"; \
	do \
		[ -e "$$f" ] || continue; \
		if [ "$(HARDENED)" = "1" ]; then \
			codesign --force --options runtime --timestamp \
				--sign "$(DEVELOPER_ID_APP)" "$$f"; \
		else \
			codesign --force --sign "$(DEVELOPER_ID_APP)" "$$f"; \
		fi; \
	done; \
	find "$(APP_BUNDLE)/Contents/Frameworks" \( -name '*.dylib' -o -name '*.framework' \) | while read f; do \
		if [ "$(HARDENED)" = "1" ]; then \
			codesign --force --options runtime --timestamp \
				--entitlements MOP.entitlements \
				--sign "$(DEVELOPER_ID_APP)" "$$f"; \
		else \
			codesign --force --sign "$(DEVELOPER_ID_APP)" "$$f"; \
		fi; \
	done; \
	echo "Signing app bundle..."; \
	if [ "$(HARDENED)" = "1" ]; then \
		codesign --force --options runtime --timestamp \
			--entitlements MOP.entitlements \
			--sign "$(DEVELOPER_ID_APP)" "$(APP_BUNDLE)"; \
	else \
		codesign --force --sign "$(DEVELOPER_ID_APP)" "$(APP_BUNDLE)"; \
	fi; \
	echo "Verifying bundled dynamic libraries..."; \
	DEPS_FILE="$$(mktemp)"; \
	trap 'rm -f "$$DEPS_FILE"' EXIT; \
	otool -L "$$APP_BINARY" | awk '$$1 ~ /^@rpath\// { print $$1 }' > "$$DEPS_FILE"; \
	while IFS= read -r dependency; do \
		dependency_path="$${dependency#@rpath/}"; \
		[ -e "$(APP_BUNDLE)/Contents/Frameworks/$$dependency_path" ] || { echo "Error: bundled @rpath dependency missing: $$dependency"; exit 1; }; \
	done < "$$DEPS_FILE"; \
	echo "✅ Bundled dependencies verified."; \
	echo "Installing to /Applications/$(APP_NAME).app..."; \
	rm -rf "/Applications/$(APP_NAME).app"; \
	cp -R "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"; \
	echo "✅ $(APP_DISPLAY) $(VERSION) installed to /Applications."

notarize: HARDENED=1
notarize: bundle
	@[ -n "$(DEVELOPER_ID_APP)" ] || { echo "Error: DEVELOPER_ID_APP not set"; exit 1; }
	@mkdir -p "$(DIST_DIR)"
	@DMG="$(DIST_DIR)/MOP-$(VERSION).dmg"; \
	ZIP="$(DIST_DIR)/MOP-$(VERSION).zip"; \
	echo "Creating DMG..."; \
	STAGE="$(DIST_DIR)/dmg-stage"; \
	rm -rf "$$STAGE" && mkdir -p "$$STAGE"; \
	cp -R "$(APP_BUNDLE)" "$$STAGE/"; \
	ln -s /Applications "$$STAGE/Applications"; \
	hdiutil create -volname "$(APP_DISPLAY)" -srcfolder "$$STAGE" -ov -format UDZO "$$DMG"; \
	rm -rf "$$STAGE"; \
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

upload:
	@bash scripts/release.sh "$(VERSION)" "$(DIST_DIR)/MOP-$(VERSION).zip"

publish:
	@bash scripts/publish.sh $(filter-out publish,$(MAKECMDGOALS))

major minor fix:
	@:

# Internal: full release (notarize + upload to R2)
_publish: release
	@echo "✅ MOP $(VERSION) uploaded to R2."

# Internal: dev release (bundle + dmg/zip + upload to R2, no Apple notarization)
_publish_dev: bundle
	@mkdir -p "$(DIST_DIR)"; \
	DMG="$(DIST_DIR)/MOP-$(VERSION).dmg"; \
	ZIP="$(DIST_DIR)/MOP-$(VERSION).zip"; \
	echo "Creating DMG..."; \
	STAGE="$(DIST_DIR)/dmg-stage"; \
	rm -rf "$$STAGE" && mkdir -p "$$STAGE"; \
	cp -R "$(APP_BUNDLE)" "$$STAGE/"; \
	ln -s /Applications "$$STAGE/Applications"; \
	hdiutil create -volname "$(APP_DISPLAY)" -srcfolder "$$STAGE" -ov -format UDZO "$$DMG"; \
	rm -rf "$$STAGE"; \
	codesign --force --sign "$(DEVELOPER_ID_APP)" "$$DMG"; \
	echo "Creating ZIP for Sparkle..."; \
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$$ZIP"; \
	bash scripts/release.sh "$(VERSION)" "$$ZIP" || exit 1; \
	echo "✅ MOP $(VERSION) uploaded to R2."
