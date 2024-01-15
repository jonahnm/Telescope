BUNDLE := com.jbteam.telescope

.PHONY: all clean

all: clean
	xcodebuild clean build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO PRODUCT_BUNDLE_IDENTIFIER="$(BUNDLE)" -sdk iphoneos -scheme Telescope -configuration Debug -derivedDataPath build
	ln -sf build/Build/Products/Debug-iphoneos Payload
	rm -rf Payload/kfd.app/Frameworks
	ldid -Sent.xml Payload/Telescope.app/Telescope
	zip -r9 Telescope.ipa Payload/Telescope.app

clean:
	rm -rf build Payload Telescope.ipa
