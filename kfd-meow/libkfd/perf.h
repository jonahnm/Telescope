/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef perf_h
#define perf_h

#include "../libkfd.h"
#include "info.h"

#include "krkw/kread/kread_sem_open.h"

#include "info/static_types/miscellaneous_types.h"
#include "info/static_types/fileproc.h"
#include "info/static_types/fileglob.h"
#include "info/static_types/fileops.h"
#include "info/static_types/pmap.h"

struct kernelcache_addresses {
    uint64_t kernel_base;
    uint64_t vn_kqfilter;                     // "Invalid knote filter on a vnode!"
    uint64_t ptov_table;                      // "%s: illegal PA: 0x%llx; phys base 0x%llx, size 0x%llx"
    uint64_t gVirtBase;                       // "%s: illegal PA: 0x%llx; phys base 0x%llx, size 0x%llx"
    uint64_t gPhysBase;                       // "%s: illegal PA: 0x%llx; phys base 0x%llx, size 0x%llx"
    uint64_t gPhysSize;                       // (gPhysBase + 0x8)
    uint64_t perfmon_devices;                 // "perfmon: %s: devfs_make_node_clone failed"
    uint64_t perfmon_dev_open;                // "perfmon: attempt to open unsupported source: 0x%x"
    uint64_t cdevsw;                          // "Can't mark ptc as kqueue ok"
    uint64_t vm_pages;                        // "pmap_startup(): too many pages to support vm_page packing"
    uint64_t vm_page_array_beginning_addr;    // "pmap_startup(): too many pages to support vm_page packing"
    uint64_t vm_page_array_ending_addr;       // "pmap_startup(): too many pages to support vm_page packing"
    uint64_t vm_first_phys_ppnum;             // "pmap_startup(): too many pages to support vm_page packing"
};

// Forward declarations for helper functions.
uint64_t phystokv(struct kfd* kfd, uint64_t pa);
uint64_t vtophys(struct kfd* kfd, uint64_t va);
void perf_init(struct kfd* kfd);
void perf_run(struct kfd* kfd);
void perf_free(struct kfd* kfd);

#endif /* perf_h */
