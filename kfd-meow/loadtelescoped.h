//
//  loadtelescoped.h
//  Telescope
//
//  Created by Jonah Butler on 1/15/24.
//

#include <mach/mach.h>
#include <mach/arm/thread_status.h>
#include "trustcache.h"
#ifndef loadtelescoped_h
#define loadtelescoped_h
UInt64 load_telescope(void);
kern_return_t mach_vm_region(vm_map_t, mach_vm_address_t *, mach_vm_size_t *, vm_region_flavor_t, vm_region_info_t, mach_msg_type_number_t *, mach_port_t *);
typedef struct {
    mach_msg_header_t Head;
    mach_msg_body_t msgh_body;
    mach_msg_port_descriptor_t thread;
    mach_msg_port_descriptor_t task;
    NDR_record_t NDR;
} exception_raise_request; // the bits we need at least
typedef struct {
    mach_msg_header_t Head;
    NDR_record_t NDR;
    kern_return_t RetCode;
} exception_raise_reply;
UInt64 testKalloc(void);
void jb(void);
UInt64 helloworldtest(void);
kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);
#endif /* loadtelescoped_h */
