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
UInt64 kalloc(UInt64 size) {
    vm_address_t addr = 0;
    assert_mach(vm_allocate(mach_task_self(), &addr, size, VM_FLAGS_ANYWHERE));
    memset((void*)(addr), 0, size);
    NSLog(@"VM_ALLOCATE TO: %p",addr);
    UInt64 paddr = vtophys_kfd(addr);
    return phystokv_kfd(paddr);
}
BOOL insert_trustcache(uint64_t tcaddr) {
    uint64_t pmap_image4_trustcaches = [theobjcbridge find_pmap_image4_trust_caches] + get_kernel_slide();
    uint64_t trustcache = kread64_kfd(pmap_image4_trustcaches);
    syslog(LOG_INFO,"[*] trustcache: 0x%llx", trustcache);
    if (!trustcache) {
        kwrite64_kfd(pmap_image4_trustcaches, tcaddr);
        return YES;
    }
    uint64_t prev = 0;
    while (trustcache) {
        prev = trustcache;
        trustcache = kread64_kfd(trustcache);
    }
    
    if (@available(iOS 16, *)) {
        kwrite64_kfd(prev, tcaddr);
        kwrite64_kfd(tcaddr+8, prev);
        return YES;
    }
    
    kwrite64_kfd(prev, tcaddr);
    return YES;
}

uint64_t load_trustcache(NSString *path, uint64_t *back_addr) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        NSLog(@"[-] Failed to load trustcache, no trustcache buffer provided");
        return 0;
    }

    trustcache_file *tc = (trustcache_file *)data.bytes;
    
    uint64_t alloc_size = sizeof(trustcache_page) + data.length + 0x8;
        
    if (@available(iOS 16, *)) {
        alloc_size = sizeof(trustcache_module) + data.length + 0x8;
    }
    uint64_t tcaddr = kalloc(alloc_size);
    uint64_t payload = kalloc(alloc_size);

    if (!tcaddr) {
        NSLog(@"[-] Failed to allocate trustcache");
        return 0;
    }

    if (@available(iOS 16, *)) {
        for (int i = 0; i < data.length; ++i) {
            kwrite8_kfd(payload + i, ((uint8_t *)data.bytes)[i]);
        }
        kwrite64_kfd(tcaddr + offsetof(trustcache_module, fileptr), payload);
        kwrite64_kfd(tcaddr + offsetof(trustcache_module, module_size), data.length);
    } else {
        kwrite64_kfd(tcaddr + offsetof(trustcache_page, selfptr), tcaddr + offsetof(trustcache_page, file));

        for (int i = 0; i < data.length; ++i) {
            kwrite8_kfd(tcaddr + offsetof(trustcache_page, file) + i, ((uint8_t *)data.bytes)[i]);
        }
    }

    if (!insert_trustcache(tcaddr)) {
        return 0;
    }
    *back_addr = tcaddr;
    return alloc_size;
}
UInt64 load(void) {
    theobjcbridge = [[objcbridge alloc] init];
    NSString *TCPath = NSBundle.mainBundle.bundlePath;
    NSString *toappend = @"/basebin.tc";
    NSString *finalpath = [TCPath stringByAppendingString:toappend];
    UInt64 ret;
    UInt64 trustcache_kaddr = load_trustcache(finalpath, &ret);
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
UInt64 testkalloc(void) {
    return kalloc(0x4000);
}
