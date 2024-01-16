//
//  loadtelescoped.m
//  Telescope
//
//  Created by Jonah Butler on 1/15/24.
//

#include "libkfd.h"
#include "libkfd/perf.h"
#import <Foundation/Foundation.h>
#import "loadtelescoped.h"
#import "pplrw.h"
#import "IOSurface_Primitives.h"
objcbridge *theobjcbridge;

extern uint64_t GetTrustCacheAddress(struct kfd* kfd);

UInt64 tcload(NSString *tcPath,UInt64 *ret) {
    NSData *data = [[NSData alloc] initWithContentsOfFile:tcPath];
    if([data length] <= 0x18) {
        return 0;
    }
    
    UInt32 version = (UInt32)((unsigned char*)data.bytes)[0x0];
    if(version != 1) {
        return 1;
    }
    UInt32 count = (UInt32)((unsigned char*)data.bytes)[0x14];
    if([data length] != 0x18 + (count * 22)) {
        return 2;
    }
    UInt64 pmap_image4_trust_caches = [theobjcbridge find_pmap_image4_trust_caches];
    if(pmap_image4_trust_caches == 0x0) {
        return 3;
    }
    UInt64 mem;
    mem = IOSurface_kalloc(data.length + 0x10,true);
    [objcbridge printtologfileWithMessageout:@"[*] Kalloc'd"];
    uint64_t next = mem;
    uint64_t us = mem + 0x8;
    uint64_t tc = mem + 0x10;
    kwrite64_kfd(us, mem + 0x10);
    kwritebuf_kfd(tc, data.bytes, [data length]);
    [objcbridge printtologfileWithMessageout:[NSString stringWithFormat:@"Wrote to kalloc'd structure, structure addr: %llu",mem]];
    uint64_t pitc = pmap_image4_trust_caches + get_kernel_slide();
    dma_perform(^{
        UInt64 cur = kread64_kfd(pitc);
        kwrite64_kfd(next, cur);
        dma_writevirt64(pitc, mem);
    });
    *ret = mem;
    return 4;
}
UInt64 load(void) {
    theobjcbridge = [[objcbridge alloc] init];
    NSString *TCPath = NSBundle.mainBundle.bundlePath;
    NSString *toappend = @"/basebin.tc";
    NSString *finalpath = [TCPath stringByAppendingString:toappend];
    UInt64 ret;
    UInt64 trustcache_kaddr = tcload(finalpath,&ret);
    if(trustcache_kaddr <= 3 || trustcache_kaddr == 70 || trustcache_kaddr == 71 || trustcache_kaddr == 68 || trustcache_kaddr == 69) {
        return trustcache_kaddr;
    } else if(ret == 0) {
        return 5;
    }
    NSArray<NSString*> *telescopeinitpath = @[@"/var/jb/BaseBin/telescopeinit"];
    UInt32 telescopeinit = [theobjcbridge execCmdWithArgs:telescopeinitpath fileActions:NULL];
    if(WIFSIGNALED(telescopeinit)) {
        return 4;
    }
    return 74;
}
