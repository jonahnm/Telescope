BUNDLE := com.mizole.meow16

.PHONY: all clean

all: clean
	xcodebuild clean build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO PRODUCT_BUNDLE_IDENTIFIER="$(BUNDLE)" -sdk iphoneos -scheme kfd-meow -configuration Debug -derivedDataPath build
	ln -sf build/Build/Products/Debug-iphoneos Payload
	rm -rf Payload/kfd.app/Frameworks
	ldid -Sent.xml Payload/kfd-meow.app/kfd-meow
	zip -r9 meow16.ipa Payload/kfd-meow.app

clean:
	rm -rf build Payload meow16.ipa
