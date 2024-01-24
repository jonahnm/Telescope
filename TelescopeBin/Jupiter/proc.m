//
//  proc.m
//  Telescope
//
//  Created by Jonah Butler on 1/23/24.
//

#include "pplrw.h"
#import <Foundation/Foundation.h>
#import "proc.h"
#import "../_shared/libproc.h"
#import "libkfd.h"
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v) ([[[UI]]])
uint64_t off_p_pid = 0;
uint64_t off_p_list_le_prev = 0;
uint64_t off_proc_proc_ro = 0;
uint64_t off_vm_map_pmap = 0;
uint64_t off_task_map = 0;
void setupprocoff(void) {
    off_p_list_le_prev = 0x8;
    off_p_pid = 0x60;
    off_proc_proc_ro = 0x18;
    off_vm_map_pmap = 0x48;
    off_task_map = 0x28;
}
uint64_t proc_for_pid(pid_t pid) {
    uint64_t proc = get_kernel_proc();
    while (true) {
        if (kread32_kfd(proc + off_p_pid) == pid) {
            return proc;
        }
        
        proc = kread64_ptr_kfd(proc + off_p_list_le_prev);
        if (!proc) {
            return -1;
        }
    }

    return 0;
}

uint64_t proc_for_name(char *nm) {
    uint64_t proc = get_kernel_proc();
    char name[0x100];
    while (true) {
        pid_t pid = kread32_kfd(proc + off_p_pid);
        proc_name(pid, name, 0x100);
        if (strcmp(name, nm) == 0) {
            return proc;
        }
        proc = kread64_ptr_kfd(proc + off_p_list_le_prev);
        if (!proc) {
            return -1;
        }
    }

    return 0;
}

pid_t pid_for_name(char *nm) {
    uint64_t proc = proc_for_name(nm);
    if (proc == -1)
        return -1;
    return kread32_kfd(proc + off_p_pid);
}

uint64_t taskptr_for_pid(pid_t pid) {
    uint64_t proc_ro = kread64_ptr_kfd(proc_for_pid(pid) + off_proc_proc_ro);
    return kread64_ptr_kfd(proc_ro + 0x8);
}

uint64_t proc_get_task(uint64_t proc) {
    uint64_t proc_ro = kread64_kfd(proc + off_proc_proc_ro);
    return kread64_ptr_kfd(proc_ro + 0x8);
}

uint64_t task_get_vm_map(uint64_t task) {
    return kread64_ptr_kfd(task + off_task_map);
}

uint64_t vm_map_get_pmap(uint64_t vm_map) {
    return kread64_ptr_kfd(vm_map + off_vm_map_pmap);
}

uint64_t pmap_get_ttep(uint64_t pmap) {
    return kread64_ptr_kfd(pmap + 0x8);
}

void proc_updatecsflags(uint64_t proc, uint32_t csflags) {
    //kcall(kernel_info.kernel_functions.proc_updatecsflags, proc, csflags, 0, 0, 0, 0);
    uint64_t proc_ro = kread64_ptr_kfd(proc + off_proc_proc_ro);
    dma_perform(^{
        dma_writevirt32(proc_ro + 0x1c, csflags);
    });
}

void pid_set_csflags(pid_t pid, uint32_t csflags) {
    uint64_t proc = proc_for_pid(pid);
    if (proc == 0) {
        return;
    }
    proc_updatecsflags(proc, csflags);
}

uint32_t proc_get_csflags(uint64_t proc) {
    uint64_t proc_ro = kread64_ptr_kfd(proc + off_proc_proc_ro);
    if (@available(iOS 16, *)) {
        uint64_t p_csflags_with_p_idversion = kread64_ptr_kfd(proc_ro + 0x1c);
        return p_csflags_with_p_idversion & 0xFFFFFFFF;
    }
    uint64_t p_csflags_with_p_idversion = kread64_ptr_kfd(proc_ro + 0x1c);
    return p_csflags_with_p_idversion & 0xFFFFFFFF;
}

void task_set_flags(uint64_t task, uint64_t flags) {
    // todo: set flags
}

void proc_fix_setuid(uint64_t proc) {
    // todo: fix setuid
}
