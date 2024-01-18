xcrun -sdk iphoneos clang -Oz -Wall -Wextra -miphoneos-version-min=14.0 -framework Security -framework Foundation helper.m -o helper
ldid -Sentitlements.plist -Cadhoc helper
# /Users/knives/Developer/kfc/ct_bypass -i helper -r -o helper