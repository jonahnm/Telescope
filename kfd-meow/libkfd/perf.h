/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef perf_h
#define perf_h

#include "../libkfd.h"
#include "info.h"
#include "kfd_meow-Swift.h"

#include "krkw/kread/kread_sem_open.h"

#include "info/static_types/miscellaneous_types.h"
#include "info/static_types/fileproc.h"
#include "info/static_types/fileglob.h"
#include "info/static_types/fileops.h"
#include "info/static_types/pmap.h"

// Forward declarations for helper functions.

extern uint64_t kaddr_ptov_table;
extern uint64_t kaddr_gPhysBase;
extern uint64_t kaddr_gPhysSize;
extern uint64_t kaddr_gVirtBase;

uint64_t phystokv(struct kfd* kfd, uint64_t pa);
uint64_t vtophys(struct kfd* kfd, uint64_t va);
void perf_init(struct kfd* kfd);
void perf_ptov(struct kfd* kfd);
void perf_run(struct kfd* kfd);
void perf_free(struct kfd* kfd);

#endif /* perf_h */
