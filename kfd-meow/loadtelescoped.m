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
#define SYSTEM_VERSION_LOWER_THAN(v)                ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)
#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

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
void tcinjecttest(void) {
    NSString  *str = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/helloworld.tc"];
    NSData *data = [NSData dataWithContentsOfFile:str];
    theobjcbridge = [[objcbridge alloc] init];
    UInt64 pmap_image4_trust_caches =  [theobjcbridge find_pmap_image4_trust_caches]; //WOOO
    NSLog(@"Found pmap_image4_trust_caches at %p",pmap_image4_trust_caches);
    sleep(1);
    pmap_image4_trust_caches += get_kernel_slide();
    NSLog(@"pmap_image4_trust_caches slid: %p", pmap_image4_trust_caches);
    UInt64 alloc_size = sizeof(trustcache_module) + data.length + 0x8;
    void *mem = kalloc_msg(0x1000);
    void *payload = kalloc_msg(0x1000);
    if(mem == 0) {
        NSLog(@"Failed to allocate memory for TrustCache: %p",mem);
        exit(EXIT_FAILURE); // ensure no kpanics
    }
    NSLog(@"Writing helloworld.tc!");
    if(data == 0x0) {
        NSLog(@"Something went wrong, no trustcache buffer provided.");
    }
    kwritebuf_tcinject(payload, data.bytes, data.length);
    NSLog(@"Wrote basebin.tc!");
    sleep(1);
    NSLog(@"Writing payload!");
    kwrite64_kfd(mem + offsetof(trustcache_module, fileptr), payload);
    NSLog(@"Wrote payload!");
    sleep(1);
    NSLog(@"Writing length!");
    UInt64 len = data.length;
    kwrite64_kfd(mem + offsetof(trustcache_module, module_size),len);
    NSLog(@"Wrote length!");
    sleep(1);
    UInt64 trustcache = kread64_ptr_kfd(pmap_image4_trust_caches);
    NSLog(@"Beginning trustcache insertion!: trustcache gave: %p",trustcache);
    if(!trustcache) {
        dma_perform(^{
            dma_writevirt64(pmap_image4_trust_caches, mem);
        });
        NSLog(@"Trustcache didn't already exist, write our stuff directly, and skip to end.");
        goto done;
    }
    UInt64 prev = 0;
    NSLog(@"Entering while(trustcache)!");
    sleep(1);
    while(trustcache) {
        prev = trustcache;
        trustcache = kread64_ptr_kfd(trustcache);
    }
    NSLog(@"Final trustcache addr: %p",prev);
    sleep(1);
    sleep(1);
    NSLog(@"memkaddr: %p", mem);
    sleep(1);
    NSLog(@"Entering dma_perform!");
    sleep(1);
    dma_perform(^{
        NSLog(@"Entered dma_perform!");
        dma_writevirt64(prev, mem);
        kwrite64_kfd(mem+8, prev);
        NSLog(@"Did write!");
    });
done:
    sleep(1);
    NSLog(@"TrustCache Successfully loaded!");
}

UInt64 helloworldtest(void) {
    spawnRoot(@"/var/mobile/helloworldunsigned", @[], NULL, NULL);
    return 1;
}

UInt64 testKalloc(void) {
    return (UInt64)kalloc_msg(0x1000);
}
UInt64 testTC(void) {
    tcinjecttest();
    return 0;
}
