//
//  loadtelescoped.h
//  Telescope
//
//  Created by Jonah Butler on 1/15/24.
//

#include <mach/mach.h>
#include <mach/arm/thread_status.h>
#ifndef loadtelescoped_h
#define loadtelescoped_h
UInt64 load_telescope(void);
kern_return_t mach_vm_region(vm_map_t, mach_vm_address_t *, mach_vm_size_t *, vm_region_flavor_t, vm_region_info_t, mach_msg_type_number_t *, mach_port_t *);

#endif /* loadtelescoped_h */
