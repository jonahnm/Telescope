xcrun -sdk iphoneos clang -Oz -Wall -Wextra -miphoneos-version-min=14.0 -framework Foundation main.c -o insert_dylib
ldid -Sentitlements.plist -Cadhoc insert_dylib
/Users/knives/Developer/kfc/ct_bypass -i insert_dylib -r -o insert_dylib