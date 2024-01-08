//
//  IOSurface_Permissive.h
//  kfd-meow
//
//  Created by mizole on 2024/01/08.
//

#ifndef IOSurface_Permissive_h
#define IOSurface_Permissive_h

#include <stdio.h>

void *IOSurface_map(uint64_t phys, uint64_t size);
uint64_t IOSurface_kalloc(uint64_t size, bool leak);

#endif /* IOSurface_Permissive_h */
