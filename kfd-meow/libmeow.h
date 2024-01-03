//
//  libmeow.h
//  kfd-meow
//
//  Created by doraaa on 2023/12/17.
//

#ifndef libmeow_h
#define libmeow_h

#include <CoreFoundation/CoreFoundation.h>

#include "libkfd.h"
#include "meowfinder.h"

extern uint64_t kernel_base;
extern uint64_t kernel_slide;

extern uint64_t our_task;
extern uint64_t our_proc;
extern uint64_t kernel_task;
extern uint64_t kernproc;
extern uint64_t our_ucred;
extern uint64_t kern_ucred;

extern uint64_t gCpuTTEP;
extern uint64_t gPhysBase;
extern uint64_t gVirtBase;

extern uint64_t data__gCpuTTEP;
extern uint64_t data__gVirtBase;
extern uint64_t data__gPhysBase;

extern uint64_t func__proc_set_ucred;

uint64_t proc_get_proc_ro(uint64_t proc_ptr);
uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr);
uint64_t proc_get_ucred(uint64_t proc_ptr);

int meow(void);

#endif /* libmeow_h */
