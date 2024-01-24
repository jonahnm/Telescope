//
//  IOSurface_Permissive.h
//  kfd-meow
//
//  Created by mizole on 2024/01/08.
//

#ifndef IOSurface_Permissive_h
#define IOSurface_Permissive_h

#include <stdio.h>
#include <stdint.h>
#include <mach/mach.h>
uint64_t ipc_entry_lookup(mach_port_name_t port_name);
uint64_t kread64_smr_kfd(uint64_t where);
void *IOSurface_map(uint64_t phys, uint64_t size);
uint64_t kalloc(uint64_t size);
mach_port_t IOSurface_map_getSurfacePort(uint64_t magic);
enum {
    kOSSerializeDictionary      = 0x01000000,
    kOSSerializeArray           = 0x02000000,
    kOSSerializeSet             = 0x03000000,
    kOSSerializeNumber          = 0x04000000,
    kOSSerializeSymbol          = 0x08000000,
    kOSSerializeString          = 0x09000000,
    kOSSerializeData            = 0x0a000000,
    kOSSerializeBoolean         = 0x0b000000,
    kOSSerializeObject          = 0x0c000000,
    kOSSerializeTypeMask        = 0x7f000000,
    kOSSerializeDataMask        = 0x00ffffff,
    kOSSerializeEndCollecton    = 0x80000000,
    kOSSerializeBinarySignature = 0x000000d3,
};
#endif /* IOSurface_Permissive_h */
