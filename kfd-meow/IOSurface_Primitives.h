//
//  IOSurface_Permissive.h
//  kfd-meow
//
//  Created by mizole on 2024/01/08.
//

#ifndef IOSurface_Permissive_h
#define IOSurface_Permissive_h

#include <stdio.h>

uint64_t ipc_entry_lookup(mach_port_name_t port_name);
uint64_t kread64_smr_kfd(uint64_t where);
void *IOSurface_map(uint64_t phys, uint64_t size);
UInt64 AllocMemoryTest(size_t allox_siz);

#endif /* IOSurface_Permissive_h */
