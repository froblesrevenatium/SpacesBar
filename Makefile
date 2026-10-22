APP = SpacesBar.app
INSTALL_DIR = /Applications

build:
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	swiftc -O -o "$(APP)/Contents/MacOS/SpacesBar" main.swift
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

install: build
	-pkill -x SpacesBar
	rm -rf "$(INSTALL_DIR)/$(APP)"
	cp -R "$(APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP)"

uninstall:
	-pkill -x SpacesBar
	rm -rf "$(INSTALL_DIR)/$(APP)"

.PHONY: build install uninstall
