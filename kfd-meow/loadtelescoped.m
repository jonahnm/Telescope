//
//  loadtelescoped.m
//  Telescope
//
//  Created by Jonah Butler on 1/15/24.
//

#include "libkfd.h"
#import <UIKit/UIKit.h>
#include <stdint.h>
#include <stdbool.h>
#import <Foundation/Foundation.h>
#include "loadtelescoped.h"
#import "pplrw.h"
#import "IOSurface_Primitives.h"
#import "libkfd/perf.h"
#import "kallocation.h"
#import "../TelescopeBin/_shared/IOKit/IOKitLib.h"
#import <zstd.h>
#import "../TelescopeBin/_shared/xpc/xpc.h"
#define SYSTEM_VERSION_LOWER_THAN(v)                ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)
#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
// Thanks KpwnZ for the launchd stuff here.
#define ROUTINE_LOAD 800
#define ROUTINE_UNLOAD 801
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
#define BOOT_INFO_PATH prebootPath(@"basebin/boot_info.plist")

extern void AppendLog(NSString *format, ...) ;

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
struct _os_alloc_once_s {
  long once;
  void *ptr;
};

struct xpc_global_data {
  uint64_t a;
  uint64_t xpc_flags;
  mach_port_t task_bootstrap_port; /* 0x10 */
#ifndef _64
  uint32_t padding;
#endif
  xpc_object_t xpc_bootstrap_pipe; /* 0x18 */
  // and there's more, but you'll have to wait for MOXiI 2 for those...
  // ...
};

extern struct _os_alloc_once_s _os_alloc_once_table[];
extern void *_os_alloc_once(struct _os_alloc_once_s *slot, size_t sz,
                            os_function_t init);

xpc_object_t launchd_xpc_send_message(xpc_object_t xdict) {
  void *pipePtr = NULL;

  if (_os_alloc_once_table[1].once == -1) {
    pipePtr = _os_alloc_once_table[1].ptr;
  } else {
    pipePtr = _os_alloc_once(&_os_alloc_once_table[1], 472, NULL);
    if (!pipePtr)
      _os_alloc_once_table[1].once = -1;
  }

  xpc_object_t xreply = nil;
  if (pipePtr) {
    struct xpc_global_data *globalData = pipePtr;
    xpc_object_t pipe = globalData->xpc_bootstrap_pipe;
    if (pipe) {
      int err = xpc_pipe_routine_with_flags(pipe, xdict, &xreply, 0);
      if (err != 0) {
        return nil;
      }
    }
  }
  return xreply;
}

int64_t launchctl_load(const char *plistPath, bool unload) {
  xpc_object_t pathArray = xpc_array_create_empty();
  xpc_array_set_string(pathArray, XPC_ARRAY_APPEND, plistPath);

  xpc_object_t msgDictionary = xpc_dictionary_create_empty();
  xpc_dictionary_set_uint64(msgDictionary, "subsystem", 3);
  xpc_dictionary_set_uint64(msgDictionary, "handle", 0);
  xpc_dictionary_set_uint64(msgDictionary, "type", 1);
  xpc_dictionary_set_bool(msgDictionary, "legacy-load", true);
  xpc_dictionary_set_bool(msgDictionary, "enable", false);
  xpc_dictionary_set_uint64(msgDictionary, "routine",
                            unload ? ROUTINE_UNLOAD : ROUTINE_LOAD);
  xpc_dictionary_set_value(msgDictionary, "paths", pathArray);

  xpc_object_t msgReply = launchd_xpc_send_message(msgDictionary);

  char *msgReplyDescription = xpc_copy_description(msgReply);
  AppendLog(@"[jbinit] msgReply = %s\n", msgReplyDescription);
  free(msgReplyDescription);

  int64_t bootstrapError =
      xpc_dictionary_get_int64(msgReply, "bootstrap-error");
  if (bootstrapError != 0) {
    AppendLog(@"[jbinit] bootstrap-error = %s\n",
          xpc_strerror((int32_t)bootstrapError));
    return bootstrapError;
  }

  int64_t error = xpc_dictionary_get_int64(msgReply, "error");
  if (error != 0) {
    AppendLog(@"[jbinit]error = %s\n", xpc_strerror((int32_t)error));
    return error;
  }

  // launchctl seems to do extra things here
  // like getting the audit token via xpc_dictionary_get_audit_token
  // or sometimes also getting msgReply["req_pid"] and msgReply["rec_execcnt"]
  // but we don't really care about that here

  return 0;
}
objcbridge *theobjcbridge;
extern int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr); // this gives me the heebeejeebees (or however the fuck you spell it)
extern int userspaceReboot(void);

size_t kwritebuf_tcinject(uint64_t where, const void *p, size_t size) {
    size_t remainder = size % 8;
    if (remainder == 0)
        remainder = 8;
    size_t tmpSz = size + (8 - remainder);
    if (size == 0)
        tmpSz = 0;

    uint64_t *dstBuf = (uint64_t *)p;
    size_t alignedSize = (size & ~0b111);

    for (int i = 0; i < alignedSize; i+=8){
        kwrite64_kfd(where + i, dstBuf[i/8]);
    }
    if (size > alignedSize) {
        uint64_t val = kread64_kfd(where + alignedSize);
        memcpy(&val, ((uint8_t*)p) + alignedSize, size-alignedSize);
        kwrite64_kfd(where + alignedSize, val);
    }
    return size;
}
void *alloc(UInt64 size) {
    UInt64 toret = 0;
    vm_allocate(mach_task_self(), &toret, size, VM_FLAGS_ANYWHERE | VM_FLAGS_PERMANENT);
    return (void*)toret;
}
void loadtc(NSString *path) {
    NSString  *str = path;
    NSData *data = [NSData dataWithContentsOfFile:str];
    theobjcbridge = [[objcbridge alloc] init];
    UInt64 pmap_image4_trust_caches =  [theobjcbridge find_pmap_image4_trust_caches]; //WOOO
    AppendLog(@"Found pmap_image4_trust_caches at %p",pmap_image4_trust_caches);
    sleep(1);
    pmap_image4_trust_caches += get_kernel_slide();
    AppendLog(@"pmap_image4_trust_caches slid: %p", pmap_image4_trust_caches);
    UInt64 alloc_size = sizeof(trustcache_module) + data.length + 0x8;
    void *mem = kalloc_msg(alloc_size);
    void *payload = kalloc_msg(alloc_size);
    if(mem == 0) {
        AppendLog(@"Failed to allocate memory for TrustCache: %p",mem);
        exit(EXIT_FAILURE); // ensure no kpanics
    }
    AppendLog(@"Writing helloworld.tc!");
    if(data == 0x0) {
        AppendLog(@"Something went wrong, no trustcache buffer provided.");
    }
    kwritebuf_tcinject(payload, data.bytes, data.length);
    AppendLog(@"Wrote basebin.tc!");
    sleep(1);
    AppendLog(@"Writing payload!");
    kwrite64_kfd(mem + offsetof(trustcache_module, fileptr), payload);
    AppendLog(@"Wrote payload!");
    sleep(1);
    AppendLog(@"Writing length!");
    UInt64 len = data.length;
    kwrite64_kfd(mem + offsetof(trustcache_module, module_size),len);
    AppendLog(@"Wrote length!");
    sleep(1);
    UInt64 trustcache = kread64_ptr_kfd(pmap_image4_trust_caches);
    AppendLog(@"Beginning trustcache insertion!: trustcache gave: %p",trustcache);
    if(!trustcache) {
        dma_perform(^{
            dma_writevirt64(pmap_image4_trust_caches, mem);
        });
        AppendLog(@"Trustcache didn't already exist, write our stuff directly, and skip to end.");
        goto done;
    }
    UInt64 prev = 0;
    AppendLog(@"Entering while(trustcache)!");
    sleep(1);
    while(trustcache) {
        prev = trustcache;
        trustcache = kread64_ptr_kfd(trustcache);
    }
    AppendLog(@"Final trustcache addr: %p",prev);
    sleep(1);
    sleep(1);
    AppendLog(@"memkaddr: %p", mem);
    sleep(1);
    AppendLog(@"Entering dma_perform!");
    sleep(1);
    dma_perform(^{
        AppendLog(@"Entered dma_perform!");
        dma_writevirt64(prev, mem);
        kwrite64_kfd(mem+8, prev);
        AppendLog(@"Did write!");
    });
done:
    sleep(1);
    AppendLog(@"TrustCache Successfully loaded!");
}
NSString *bootmanifesthash(void) {
    io_registry_entry_t entry = IORegistryEntryFromPath(kIOMasterPortDefault, "IODeviceTree:/chosen");
    if(entry == MACH_PORT_NULL) {
        return @"";
    }
    CFTypeRef hash = IORegistryEntryCreateCFProperty(entry, CFSTR("boot-manifest-hash"), kCFAllocatorDefault, 0);
    NSData *data = (__bridge NSData*)hash;
    NSString *ret = @"";
    const unsigned char *bytes = [data bytes];
    for(int i = 0; i < 1024; i++) {
        NSString *toappend = [NSString stringWithFormat:@"%02X",bytes[i]];
    }
    return ret;
}
NSString *locateexistingfakeroot(void) {
    NSString *hash = bootmanifesthash();
    if([hash isEqualToString:@""]) {
        return hash;
    }
    NSURL *ppURL = [NSURL fileURLWithPath:[@"/private/preboot/" stringByAppendingString:hash]];
    NSArray *candidates = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:ppURL includingPropertiesForKeys:nil options:@[] error:nil];
    if(candidates == nil) {
        return @"";
    }
    for(NSURL *candidate in candidates) {
        if([[candidate lastPathComponent] hasPrefix:@"jb-"]) {
            return [candidate path];
        }
    }
    return @"";
}
NSString *generatefakerootpath(void) {
    const char *letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    char *result = malloc(6*sizeof(char));
    for(int counter = 0; counter < 6; counter++) {
        UInt32 randomindex = arc4random_uniform((UInt32)strlen(letters));
        const char randomchar = letters[randomindex];
        result[counter] = randomchar;
    }
    NSString *toret = [NSString stringWithFormat:@"/private/preboot/%s/jb-%s",[bootmanifesthash() cStringUsingEncoding:NSUTF8StringEncoding],result];
    free(result);
    return toret;
}
void UUIDFixer(void) {
    NSString *path = [@"/private/preboot/" stringByAppendingString:bootmanifesthash()];
    struct stat pathstat;
    if(stat([path cStringUsingEncoding:NSUTF8StringEncoding],&pathstat) != 0) {
        //TODO: THROW ERRORS
        return;
    }
    uid_t curownerid = pathstat.st_uid;
    gid_t curgroupid = pathstat.st_gid;
    if(curownerid != 0 || curgroupid != 0) {
        if(chown([path cStringUsingEncoding:NSUTF8StringEncoding],0,0) != 0) {
            //TODO: THROW ERRORS
            return;
        }
    }
    mode_t perms = pathstat.st_mode & S_IRWXU;
    
    if(perms != 493) {
        if(chmod([path cStringUsingEncoding:NSUTF8StringEncoding],493) != 0) {
            // TODO: THROW ERRORS
            return;
        }
    }
}
void gimmeRoot(void) {
    uint64_t proc_ro = kread64_ptr_kfd(get_current_proc() + 0x18);
    uint64_t ucreds  = kread64_ptr_kfd(proc_ro + 0x20);
    uint64_t cr_posix_p = ucreds + 0x18;
    dma_perform(^{
        dma_writevirt32(cr_posix_p + 0,0x0); // yummy root
    });
}
void untar(NSString *tarpath,NSString *target,bool isgz) {
    NSString *bin = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/tar"];
    // 493 is the decimal representation of the 755 octal btw
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @493} ofItemAtPath:bin error:nil];
    if(isgz) {
        spawnRoot(bin, @[@"-xvzf",tarpath,@"-C",target], nil, nil);
    } else {
        spawnRoot(bin, @[@"-xf",tarpath,@"-C",target], nil, nil);
    }
}
void createsymboliclink(NSString *path,NSString *pathdest) {
    NSMutableArray *comps = [NSMutableArray arrayWithArray:[path componentsSeparatedByString:@"/"]];
    [comps removeLastObject];
    NSString *dirpath = [NSString pathWithComponents:comps];
    if(![[NSFileManager defaultManager] fileExistsAtPath:dirpath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirpath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:path withDestinationPath:pathdest error:nil];
}
void unZSTD(NSString *path, NSString *target) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    UInt64 len = ZSTD_getFrameContentSize(data.bytes, data.length);
    void *decompressed = malloc(len);
    ZSTD_decompress(decompressed, len, data.bytes, data.length);
    NSData *outdata = [NSData dataWithBytes:decompressed length:len];
    [[NSFileManager defaultManager] createFileAtPath:target contents:outdata attributes:nil];
    free(decompressed);
}
bool fileosymlinkexists(NSString *path) {
    NSFileManager *manager = [NSFileManager defaultManager];
    if([manager fileExistsAtPath:path]) {
        return true;
    }
    @try {
        NSDictionary *attr = [manager attributesOfItemAtPath:path error:nil];
        NSFileAttributeType filetype = [attr fileType];
        if(filetype == NSFileTypeSymbolicLink) {
            return true;
        }
    } @catch(NSException* e) {}
    return false;
}
// credit to opa334 for making this function
void patchBaseBinLaunchDaemonPlist(NSString *plistPath)
{
    NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (plistDict) {
        NSMutableArray *programArguments = ((NSArray *)plistDict[@"ProgramArguments"]).mutableCopy;
        if (programArguments.count >= 1) {
            NSString *pathBefore = programArguments[0];
            if (![pathBefore hasPrefix:@"/private/preboot"]) {
                programArguments[0] = prebootPath(pathBefore);
                plistDict[@"ProgramArguments"] = programArguments.copy;
                [plistDict writeToFile:plistPath atomically:YES];
            }
        }
    }
}
void bootstrap(void) {
    //kopen(2,false);
    NSString *basebintc = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/basebin.tc"];
    NSString *tartc = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/tar.tc"];
    loadtc(basebintc);
    sleep(1);
    loadtc(tartc);
    NSString *tarbin = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/tar"];
    spawnRoot(@"/sbin/mount",@[@"-u", @"-w",@"/private/preboot"],nil,nil);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    @try {
        NSDictionary *attr = [fileManager attributesOfItemAtPath:@"/var/jb" error:nil];
        NSFileAttributeType filetype = [attr fileType];
        if(filetype == NSFileTypeSymbolicLink) {
            [fileManager removeItemAtPath:@"/var/jb" error:nil];
        }
    } @catch (NSException *exception) {}
    if([fileManager fileExistsAtPath:@"/var/jb"]) {
        [fileManager removeItemAtPath:@"/var/jb" error:nil];
    }
    NSString *fakerootpath = locateexistingfakeroot();
    if([fakerootpath isEqualToString:@""]) {
        fakerootpath = generatefakerootpath();
        [[NSFileManager defaultManager] createDirectoryAtPath:fakerootpath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    bool needtoextractbs = false;
    NSString *procursuspath = [fakerootpath stringByAppendingString:@"/procursus"];
    NSString *installedpath = [fakerootpath stringByAppendingString:@".installed_telescope"];
    if([[NSFileManager defaultManager] fileExistsAtPath:procursuspath]) {
        if(![[NSFileManager defaultManager] fileExistsAtPath:installedpath]) {
            [[NSFileManager defaultManager] removeItemAtPath:procursuspath error:nil];
        }
    }
    if(![[NSFileManager defaultManager] fileExistsAtPath:procursuspath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:procursuspath withIntermediateDirectories:YES attributes:nil error:nil];
        needtoextractbs = true;
    }
    NSString *basebintarpath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/basebin.tar.gz"];
    NSString *basebinpath = [procursuspath stringByAppendingString:@"/basebin"];
    if([[NSFileManager defaultManager] fileExistsAtPath:basebinpath]) {
        [[NSFileManager defaultManager] removeItemAtPath:basebinpath error:nil];
    }
    untar(basebintarpath,procursuspath,true);
    createsymboliclink(@"/var/jb", procursuspath);
    if(needtoextractbs) {
        NSString *bszstdpath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/bootstrap-iphoneos-arm64.tar.zst"];
        NSString *bootstraptmptarpath = [NSTemporaryDirectory() stringByAppendingString:@"bootstrap-iphoneos-arm64.tar"];
        if([[NSFileManager defaultManager] fileExistsAtPath:bootstraptmptarpath]) {
            [[NSFileManager defaultManager] removeItemAtPath:bootstraptmptarpath error:nil];
        }
        unZSTD(bszstdpath, bootstraptmptarpath);
        untar(bootstraptmptarpath, @"/", false);
        [[NSFileManager defaultManager] removeItemAtPath:bootstraptmptarpath error:nil];
        [@"" writeToFile:installedpath atomically:YES encoding: NSUTF8StringEncoding error:nil];
    }
        NSString *defaultsources = @"Types: deb \
    URIs: https://repo.chariz.com/ \
    Suites: ./ \
    Components: \
        \
    Types: deb \
    URIs: https://havoc.app/ \
    Suites: ./ \
    Components: \
    \
    Types: deb \
    URIs: http://apt.thebigboss.org/repofiles/cydia/ \
    Suites: stable \
    Components: main \
    \
    Types: deb \
    URIs: https://ellekit.space/ \
    Suites: ./ \
    Components:";
        [defaultsources writeToFile:@"/var/jb/etc/apt/sources.list.d/default.sources" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        if(!fileosymlinkexists(@"/var/jb/usr/bin/opainject")) {
            createsymboliclink(@"/var/jb/usr/bin/opainject", [procursuspath stringByAppendingString:@"/basebin/opainject"]);
            if(![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/var/mobile/Library/Preferences"]) {
                NSDictionary *attrs = @{
                    NSFilePosixPermissions: @493,
                    NSFileOwnerAccountID: @501,
                    NSFileGroupOwnerAccountID: @501
                };
                [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/jb/var/mobile/Library/Preferences" withIntermediateDirectories:YES attributes:attrs error:nil];
            }
            NSURL *bootinfoURL = [NSURL fileURLWithPath:@"/var/jb/basebin/boot_info.plist"];
            NSDictionary *boot_infoconts = @{
                @"ptov_table": [NSNumber numberWithUnsignedLongLong:kaddr_ptov_table],
                @"gPhysBase": [NSNumber numberWithUnsignedLongLong:kaddr_gPhysBase],
                @"gPhysSize": [NSNumber numberWithUnsignedLongLong:kaddr_gPhysSize],
                @"gVirtBase": [NSNumber numberWithUnsignedLongLong:kaddr_gVirtBase]
            };
            [boot_infoconts writeToURL:bootinfoURL atomically:YES];
    }
}
// This won't work atm as I need to add Jupiter's trustcache functions.
void finbootstrap(void) {
    spawnRoot(@"/var/jb/bin/sh", @[@"/var/jb/prep_bootstrap.sh"], nil, nil);
    spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-i",[[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/Sileo.deb"]], nil, nil);
}
void jb(void) {
    gimmeRoot();
    setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin:/var/jb/sbin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/usr/bin", 1);
    setenv("TERM","xterm-256color",1);
    bootstrap();
    patchBaseBinLaunchDaemonPlist(prebootPath(@"basebin/LaunchDaemons/jupiter.plist"));
    kclose(_kfd);
    launchctl_load([prebootPath(@"basebin/LaunchDaemons/jupiter.plist") cStringUsingEncoding:NSUTF8StringEncoding], false);
    // This is where I would ask jupiter to rebuild trustcache for the bootstrap, but I haven't gotten to that yet
    if([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/prep_bootstrap.sh"]) {
        finbootstrap();
    }
}

UInt64 helloworldtest(void) {
    spawnRoot(@"/var/mobile/helloworldunsigned", @[], NULL, NULL);
    return 1;
}

UInt64 testKalloc(void) {
    return (UInt64)kalloc_msg(0x1000);
}
