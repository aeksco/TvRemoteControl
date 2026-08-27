BUNDLE_ID   := aeksco.TvRemoteControl
PROJECT     := TvRemoteControl.xcodeproj
SCHEME      := TvRemoteControl
DERIVED     := build/DerivedData
APP         := $(DERIVED)/Build/Products/Debug/TvRemoteControl.app

# Release build products land in dist/ so the shippable .app sits at the repo root.
REL_DERIVED := build/ReleaseDerivedData
REL_APP     := $(REL_DERIVED)/Build/Products/Release/TvRemoteControl.app
DIST        := dist
DIST_APP    := $(DIST)/TvRemoteControl.app

ICONSET     := TvRemoteControl/Assets.xcassets/AppIcon.appiconset

.PHONY: app release release-zip icon run test spike spike-seize reset-tcc clean

app:
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build | grep -E 'error|warning: |BUILD'

# Signed, hardened-runtime Release build copied to dist/TvRemoteControl.app.
# Without a Developer ID cert this signs with the Apple Development identity, which
# runs on this Mac but is Gatekeeper-quarantined elsewhere until it's notarized.
release:
	rm -rf $(DIST_APP)
	mkdir -p $(DIST)
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(REL_DERIVED) clean build | grep -E 'error|warning: |BUILD'
	ditto $(REL_APP) $(DIST_APP)
	codesign --verify --strict --verbose=2 $(DIST_APP)
	@echo
	@echo "  $(DIST_APP)  ($$(du -sh $(DIST_APP) | cut -f1))"
	@codesign -dv $(DIST_APP) 2>&1 | grep -E 'Identifier|Authority|Signature' | sed 's/^/  /'

release-zip: release
	rm -f $(DIST)/TvRemoteControl.zip
	ditto -c -k --keepParent $(DIST_APP) $(DIST)/TvRemoteControl.zip
	@echo "  $(DIST)/TvRemoteControl.zip"

# Redraws AppIcon.appiconset from Tools/appicon/GenerateAppIcon.swift.
icon:
	swift Tools/appicon/GenerateAppIcon.swift $(ICONSET)

run: app
	pkill -x TvRemoteControl || true
	open "$(APP)"

test:
	cd Packages/RemoteCore && swift test

spike:
	cd Tools/hidspike && swift run hidspike

spike-seize:
	cd Tools/hidspike && swift run hidspike --seize

# TCC remembers grants per code signature; reset between runs when things get confusing.
reset-tcc:
	tccutil reset ListenEvent $(BUNDLE_ID)
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf $(DERIVED) $(REL_DERIVED) $(DIST) Tools/hidspike/.build
