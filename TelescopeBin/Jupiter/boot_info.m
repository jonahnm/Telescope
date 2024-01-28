#include "boot_info.h"
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <_types/_uint64_t.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef UInt32 IOOptionBits;
#define IO_OBJECT_NULL ((io_object_t)0)
typedef mach_port_t io_object_t;
typedef io_object_t io_registry_entry_t;
extern const mach_port_t kIOMainPortDefault;
typedef char io_string_t[512];

kern_return_t IOObjectRelease(io_object_t object);

io_registry_entry_t IORegistryEntryFromPath(mach_port_t, const io_string_t);

CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry,
                                          CFStringRef key,
                                          CFAllocatorRef allocator,
                                          IOOptionBits options);

#ifdef __cplusplus
}
#endif
#define BOOT_INFO_PATH @"/var/jb/baseboin/boot_info.plist"

NSString *prebootPath(NSString *path) {
    static NSString *sPrebootPrefix = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        NSMutableString *bootManifestHashStr;
        io_registry_entry_t registryEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen");
        if(registryEntry) {
            CFDataRef bootManifestHash = (CFDataRef)IORegistryEntryCreateCFProperty(registryEntry, CFSTR("boot-manifest-hash"), kCFAllocatorDefault, 0);
            if(bootManifestHash) {
                const UInt8 *buffer = CFDataGetBytePtr(bootManifestHash);
                bootManifestHashStr = [NSMutableString stringWithCapacity:(CFDataGetLength(bootManifestHash) *2)];
                for(CFIndex i = 0; i < CFDataGetLength(bootManifestHash); i++) {
                    [bootManifestHashStr appendFormat:@"%02X",buffer[i]];
                }
                CFRelease(bootManifestHash);
            }
            if(bootManifestHashStr) {
                NSString *activePrebootPath = [@"/private/preboot/" stringByAppendingPathComponent:bootManifestHashStr];
                NSArray *subItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil];
                for(NSString *subItem in subItems) {
                    if([subItem hasPrefix:@"jb-"]) {
                        sPrebootPrefix = [[activePrebootPath stringByAppendingPathComponent:subItem] stringByAppendingPathComponent:@"procursus"];
                        break;
                    }
                }

            } else {
                sPrebootPrefix = @"/var/jb";
            }
        }
    });
    if(path) {
        return [sPrebootPrefix stringByAppendingPathComponent:path];
    } else {
        return sPrebootPrefix;
    }
}
void bootInfo_setObject(NSString *name,__kindof NSObject *object) {
    NSMutableDictionary *bootInfo = [NSDictionary dictionaryWithContentsOfFile:BOOT_INFO_PATH]
    .mutableCopy
    ?: [NSMutableDictionary new];
    if(object) {
        bootInfo[name] = object;
    } else {
        [bootInfo removeObjectForKey:name];
    }
    [bootInfo writeToFile:BOOT_INFO_PATH atomically:YES];
}
__kindof NSObject *bootInfo_getObject(NSString *name) {
    NSDictionary *bootInfo = [NSDictionary dictionaryWithContentsOfFile:BOOT_INFO_PATH];
    return bootInfo[name];
}
uint64_t bootInfo_getUInt64(NSString *name) {
    NSNumber *num = bootInfo_getObject(name);
    if([num isKindOfClass:NSNumber.class]) {
        return num.unsignedLongLongValue;
    }
    return 0;
}
uint64_t bootInfo_getSlidUInt64(NSString *name) {
    uint64_t kernelslide = bootInfo_getUInt64(@"kernelslide");
    return bootInfo_getUInt64(name) + kernelslide;
}
NSData *bootInfo_getData(NSString *name) {
    NSData *data = bootInfo_getObject(name);
    if([data isKindOfClass:NSData.class]) {
        return data;
    }
    return nil;
}
NSArray *bootInfo_getArray(NSString *name) {
    NSArray *array = bootInfo_getObject(name);
    if([array isKindOfClass:NSArray.class]) {
        return array;
    }
    return nil;
}