TARGET = amfidpatch.dylib
CC = clang

CFLAGS = -framework Foundation -framework CoreServices -framework IOSurface -framework CoreGraphics -framework IOKit -framework Security -I../_shared -I./src -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -arch arm64e -miphoneos-version-min=15.0 -fobjc-arc -O2 
LDFLAGS = -dynamiclib -L./ -lbsm -lresolv -F./Frameworks

sign: $(TARGET)
	@ldid -S $^

#  $(TARGET): $(wildcard src/opainject/*.m src/*.m src/*.c src/console/*.c)

$(TARGET): $(wildcard src/*.mm src/*.m src/*.c)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	@rm -f $(TARGET)