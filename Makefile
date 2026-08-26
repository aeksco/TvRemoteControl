BUNDLE_ID   := aeksco.TvRemoteControl
DERIVED     := build/DerivedData
APP         := $(DERIVED)/Build/Products/Debug/TvRemoteControl.app

.PHONY: app run test spike spike-seize reset-tcc clean

app:
	set -o pipefail; xcodebuild -project TvRemoteControl.xcodeproj -scheme TvRemoteControl -configuration Debug \
		-derivedDataPath $(DERIVED) build | grep -E 'error|warning: |BUILD'

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
	rm -rf $(DERIVED) Tools/hidspike/.build
