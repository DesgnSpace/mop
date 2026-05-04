APP_NAME      := MOP
BUILD_DIR     := .build
APP_BUNDLE    := $(CURDIR)/$(APP_NAME).app
BIN_INSTALL   := /usr/local/bin/mop
LAUNCHD_LABEL := com.mop
PLIST_PATH    := $(HOME)/Library/LaunchAgents/$(LAUNCHD_LABEL).plist
LOG_DIR       := $(HOME)/Library/Logs
VERSION       ?= $(shell cat VERSION)

.PHONY: build run bundle install uninstall start stop help

help:
	@echo "Targets:"
	@echo "  build                    swift build (debug)"
	@echo "  run                      build + run"
	@echo "  bundle [VERSION=x.y.z]   release build, .app bundle, install to /Applications"
	@echo "  install                  install binary + launchd auto-launch service"
	@echo "  uninstall                remove binary + launchd service"
	@echo "  start                    start MOP via launchd (or directly)"
	@echo "  stop                     kill running MOP process"

build:
	swift build

run: build
	swift run $(APP_NAME)

bundle:
	@echo "Version: $(VERSION)"
	@echo "Building release binary..."
	swift build -c release
	@BINARY="$(BUILD_DIR)/release/$(APP_NAME)"; \
	[ -f "$$BINARY" ] || { echo "Error: binary not found at $$BINARY"; exit 1; }; \
	echo "Creating app bundle..."; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"; \
	cp "$$BINARY" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	[ -f Sources/AppIcon.icns ] && cp Sources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns" || true; \
	sed 's|{{VERSION}}|$(VERSION)|g' templates/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"; \
	echo "Signing..."; \
	codesign --force --deep --sign "MOP Dev" "$(APP_BUNDLE)" 2>/dev/null \
		|| codesign --force --deep --sign - "$(APP_BUNDLE)"; \
	echo "Installing to /Applications/$(APP_NAME).app..."; \
	rm -rf "/Applications/$(APP_NAME).app"; \
	cp -R "$(APP_BUNDLE)" "/Applications/$(APP_NAME).app"; \
	echo "Done. $(APP_NAME) $(VERSION) installed to /Applications."

install:
	@echo "Building release binary..."
	swift build -c release
	@BINARY="$(BUILD_DIR)/release/$(APP_NAME)"; \
	[ -f "$$BINARY" ] || { echo "Error: binary not found"; exit 1; }; \
	echo "Installing binary to $(BIN_INSTALL)..."; \
	sudo cp "$$BINARY" "$(BIN_INSTALL)"; \
	sudo chmod +x "$(BIN_INSTALL)"
	@echo "Creating launchd plist..."
	@mkdir -p "$(dir $(PLIST_PATH))"
	@sed -e 's|{{LAUNCHD_LABEL}}|$(LAUNCHD_LABEL)|g' \
	     -e 's|{{BIN_INSTALL}}|$(BIN_INSTALL)|g' \
	     -e 's|{{LOG_DIR}}|$(LOG_DIR)|g' \
	     templates/launchd.plist > "$(PLIST_PATH)"
	@launchctl unload "$(PLIST_PATH)" 2>/dev/null || true
	@launchctl load "$(PLIST_PATH)"
	@echo "MOP installed. Logs: $(LOG_DIR)/mop.log"

uninstall:
	@launchctl unload "$(PLIST_PATH)" 2>/dev/null || true
	@rm -f "$(PLIST_PATH)"
	@sudo rm -f "$(BIN_INSTALL)"
	@rm -f "$(LOG_DIR)/mop.log" "$(LOG_DIR)/mop.err"
	@echo "MOP uninstalled."

start:
	@if pgrep -x "$(APP_NAME)" >/dev/null 2>&1; then \
		echo "$(APP_NAME) is already running."; exit 0; \
	fi; \
	GUI="gui/$$(id -u)"; \
	if [ -f "$(PLIST_PATH)" ]; then \
		if launchctl print "$$GUI/$(LAUNCHD_LABEL)" >/dev/null 2>&1; then \
			launchctl kickstart "$$GUI/$(LAUNCHD_LABEL)"; \
		else \
			launchctl bootstrap "$$GUI" "$(PLIST_PATH)"; \
		fi; \
		echo "$(APP_NAME) started via launchd."; \
	elif [ -f "$(BIN_INSTALL)" ]; then \
		"$(BIN_INSTALL)" & echo "$(APP_NAME) started (PID $$!)."; \
	else \
		echo "$(APP_NAME) not installed. Run: make install"; exit 1; \
	fi

stop:
	@pkill -x "$(APP_NAME)" && echo "$(APP_NAME) stopped." || echo "$(APP_NAME) not running."
