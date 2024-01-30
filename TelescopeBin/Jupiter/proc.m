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
#import "boot_info.h"
// TODO
// TODO
// TODO
// TODO
// TODO
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
    
    return 0;
}

uint64_t proc_for_name(char *nm) {
    return 0;
}

pid_t pid_for_name(char *nm) {
   return 0;
}

uint64_t taskptr_for_pid(pid_t pid) {
   return 0;
}

uint64_t proc_get_task(uint64_t proc) {
       return 0;
}

uint64_t task_get_vm_map(uint64_t task) {
   return 0;
}

uint64_t vm_map_get_pmap(uint64_t vm_map) {
   return 0;
}

uint64_t pmap_get_ttep(uint64_t pmap) {
   return 0;
}

void proc_updatecsflags(uint64_t proc, uint32_t csflags) {
}

void pid_set_csflags(pid_t pid, uint32_t csflags) {
    
}

uint32_t proc_get_csflags(uint64_t proc) {
      return 0;
}

void task_set_flags(uint64_t task, uint64_t flags) {
    // todo: set flags
}

void proc_fix_setuid(uint64_t proc) {
    // todo: fix setuid
}
