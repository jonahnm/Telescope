#include "JupiterTCPage.h"
#include "kallocation.h"
#include "pplrw.h"
#include "trustcache_structs.h"
#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <MacTypes.h>
#include "signatures.h"
#include <stddef.h>
#include <stdint.h>
#include <mach/kern_return.h>
#include <mach/mach_init.h>
#include <IOKit/IOTypes.h>
#include <IOKit/IOKitLib.h>
#import "boot_info.h"
#import "trustcache.h"
//#import "signatures.h"
#import "proc.h"
#import "macho.h"
int tcentryComparator(const void *vp1,const void *vp2) {
    trustcache_entry2 *tc1 = (trustcache_entry2 *)vp1;
    trustcache_entry2 *tc2 = (trustcache_entry2 *)vp2;
    return memcmp(tc1->hash, tc2->hash, 20);
}
JupiterTCPage *trustCacheFindFreePage(void) {
    for(JupiterTCPage *page in gTCPages) {
        @autoreleasepool {
            if(page.amountOfSlotsLeft > 0) {
                return page;
            }
        }
    }
    return [[JupiterTCPage alloc] initAllocateAndLink];
}
BOOL isCdHashinTrustCache(NSData *cdHash) {
    kern_return_t kr;
    CFMutableDictionaryRef amfiServiceDict = IOServiceMatching("AppleMobileFileIntegrity");
    if(amfiServiceDict) {
        io_connect_t connect;
        io_service_t amfiService = IOServiceGetMatchingService(kIOMasterPortDefault, amfiServiceDict);
        kr = IOServiceOpen(amfiService, mach_task_self(), 0, &connect);
        if(kr != KERN_SUCCESS) {
            //TODO: Add some logging.
            return -2;
        }
        uint64_t includeLoadedTC = YES;
        kr = IOConnectCallMethod(connect, 6, &includeLoadedTC, 1, CFDataGetBytePtr((__bridge CFDataRef)cdHash), CFDataGetLength((__bridge CFDataRef)cdHash), 0, 0, 0, 0);
        IOServiceClose(connect);
        return kr == 0;
    }
    return NO;
}
BOOL trustCacheListAdd(uint64_t trustCacheKaddr) {
    if(!trustCacheKaddr)
        return NO;
    uint64_t pmap_image4_trust_caches = bootInfo_getSlidUInt64(@"pmap_image4_trust_caches");
    uint64_t curTc = kread_ptr(pmap_image4_trust_caches);
    if(curTc == 0) {
        dma_perform(^{
            dma_writevirt64(pmap_image4_trust_caches, trustCacheKaddr);
            kwrite64(trustCacheKaddr, 0);
        });
    } else {
        uint64_t prevTc = 0;
        while(curTc != 0) {
            prevTc = curTc;
            curTc = kread_ptr(curTc);
        }
        dma_perform(^{
            dma_writevirt64(prevTc, trustCacheKaddr);
        }); 
        kwrite64(trustCacheKaddr, 0);
        kwrite64(trustCacheKaddr + 8, prevTc);
    }
    return YES;
}
BOOL trustCacheListRemove(uint64_t trustCacheKaddr) {
    if(!trustCacheKaddr)
        return NO;
    uint64_t nextPtr = kread_ptr(trustCacheKaddr + offsetof(trustcache_page,nextPtr));
    uint64_t pmap_image4_trust_caches = bootInfo_getSlidUInt64(@"pmap_image4_trust_caches");
    uint64_t curTc = kread_ptr(pmap_image4_trust_caches);
    if(curTc == 0) {
        return NO;
    }
    else if(curTc == trustCacheKaddr) {
        dma_perform(^{
            dma_writevirt64(pmap_image4_trust_caches, nextPtr);
        });
    }else {
        uint64_t prevTc = 0;
        while(curTc != trustCacheKaddr) {
            if(curTc == 0)
                return NO;
            prevTc = curTc;
            curTc = kread_ptr(curTc);
        }
        dma_perform(^{
            dma_writevirt64(prevTc, nextPtr);
        });
    }
    return YES;
}
uint64_t staticTrustCacheUploadFile(trustcache_file *filetoUpload,size_t fileSize,size_t *outMapSize) {
    if(fileSize < sizeof(trustcache_file))
        return 0;
    size_t expectedSize = sizeof(trustcache_file) + filetoUpload->length * sizeof(trustcache_entry);
    if(expectedSize != fileSize)
        return 0;
    uint64_t mapSize = sizeof(trustcache_module) + fileSize;
    uint64_t mapKaddr = (uint64_t)kalloc_msg(mapSize);
    if(!mapKaddr)
        return 0;
    if(outMapSize)
        *outMapSize = mapSize;
    uint64_t module_size_ptr = mapKaddr + offsetof(trustcache_module,module_size);
    kwrite64(module_size_ptr, fileSize);
    uint64_t module_fileptr_ptr = mapKaddr + offsetof(trustcache_module,fileptr);
    kwrite64(module_fileptr_ptr, mapKaddr + 0x28);
    kwritebuf(mapKaddr + 0x28, filetoUpload, fileSize);
    trustCacheListAdd(mapKaddr);
    return mapKaddr;
}
void dynamicTrustCacheUploadCDHashesFromArray(NSArray *cdHashArray) {
    __block JupiterTCPage *mappedInPage = nil;
    for(NSData *cdHash in cdHashArray) {
        @autoreleasepool {
            if(!mappedInPage || mappedInPage.amountOfSlotsLeft == 0) {
                if(mappedInPage) {
                    [mappedInPage sort];
                }
            }
            trustcache_entry2 entry;
            memcpy(&entry.hash, cdHash.bytes, 20);
            entry.hash_type = 0x2;
            entry.flags = 0x0;
            [mappedInPage addEntry2:entry];
        }
    }
    if(mappedInPage) {
        [mappedInPage sort];
    }
    usleep(10000);
    [mappedInPage updateTCPage];
}
int processBinary(NSString *binaryPath) {
     if(!binaryPath)
        return 0;
    if(![[NSFileManager defaultManager] fileExistsAtPath:binaryPath]) {
        return 0;
    }
    int ret = 0;
    FILE *machoFile = fopen(binaryPath.fileSystemRepresentation, "rb");
    if(!machoFile)
        return 1;
    if(machoFile) {
        bool isMacho = NO;
        bool isLibrary = NO;
        machoGetInfo(machoFile, &isMacho, &isLibrary);
        if(isMacho) {
            int64_t bestArchCandidate = machoFindBestArch(machoFile);
            if(bestArchCandidate >= 0) {
                uint32_t bestArch = bestArchCandidate;
                NSMutableArray *nonTrustCachedCDHashes = [NSMutableArray new];
                void (^tcCheckBlock)(NSString *) = ^(NSString *dependencyPath) {
                    if(dependencyPath) {
                        NSURL *dependencyURL = [NSURL fileURLWithPath:dependencyPath];
                        NSData *cdHash = nil;
                        BOOL isAdhocSigned = NO;
                        evaluateSignature(dependencyURL, &cdHash, &isAdhocSigned);
                        if(isAdhocSigned) {
                            if(!isCdHashinTrustCache(cdHash)) {
                                [nonTrustCachedCDHashes addObject:cdHash];
                            }
                        }
                    }
                };
                tcCheckBlock(binaryPath);
                machoEnumerateDependencies(machoFile,bestArch,binaryPath,tcCheckBlock);
                dynamicTrustCacheUploadCDHashesFromArray(nonTrustCachedCDHashes);
            } else {
                ret = 3;
            }
        } else {
            ret = 2;
        }
        fclose(machoFile);
    } else {
        ret = 1;
    }
    return ret;
}
void fileEnumerateTrustCacheEntries(NSURL *filePath, void (^enumerateBlock)(trustcache_entry entry)) {
    NSData *cdHash = nil;
    BOOL adhocSigned = NO;
    int evalRet = evaluateSignature(filePath, &cdHash, &adhocSigned);
    if(evalRet == 0) {
        if(adhocSigned) {
            if([cdHash length] == CS_CDHASH_LEN) {
                trustcache_entry entry;
                memcpy(&entry.hash,[cdHash bytes],CS_CDHASH_LEN);
                entry.hash_type = 0x2;
                entry.flags = 0x0;
                enumerateBlock(entry);
            }
        }else if(evalRet != 4) {
            // add some logging
        }
    }
}
void dynamicTrustCacheUploadDirectory(NSString *directoryPath) {
    NSString *basebinPath = [[@"/var/jb/baseboin" stringByResolvingSymlinksInPath] stringByStandardizingPath];
    NSString *resolvedPath = [[directoryPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    NSLog(@"resolvedPath: %@",resolvedPath);
    NSURL *resolvedURL = [NSURL fileURLWithPath:resolvedPath isDirectory:YES];
    NSDirectoryEnumerator<NSURL *> *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:resolvedURL includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey] options:0 errorHandler:nil];
    __block JupiterTCPage *mappedInPage = nil;
    for(NSURL *enumURL in directoryEnumerator) {
        @autoreleasepool {
            NSNumber *isSymlink;
            [enumURL getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil];
            if(isSymlink && ![isSymlink boolValue]) {
                if([[[enumURL.path stringByResolvingSymlinksInPath] stringByStandardizingPath] hasPrefix:basebinPath])
                    continue;
                fileEnumerateTrustCacheEntries(enumURL, ^(trustcache_entry entry) {
                    if(!mappedInPage || mappedInPage.amountOfSlotsLeft == 0) {
                        if(mappedInPage) {
                            [mappedInPage sort];
                        }
                        mappedInPage = trustCacheFindFreePage();
                    }
                    trustcache_entry2 entry2;
                    memcpy(&entry2.hash,entry.hash,CS_CDHASH_LEN);
                    entry2.hash_type =  entry.hash_type;
                    entry2.flags = entry.flags;
                    [mappedInPage addEntry2:entry2];
                });
            }
        }
    }
 if(mappedInPage) {
            [mappedInPage sort];
        }
        [mappedInPage updateTCPage];
}
void rebuildDynamicTrustCache(void) {
    for(JupiterTCPage *page in [gTCPages reverseObjectEnumerator]) {
        @autoreleasepool {
            [page unlinkAndFree];
        }
    }
    dynamicTrustCacheUploadDirectory(@"/var/jb");
}
