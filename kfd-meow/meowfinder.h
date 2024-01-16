//
//  meowfinder.h
//  meow
//
//  Created by doraaa on 2023/10/15.
//

#ifndef meowfinder_h
#define meowfinder_h

#include <stdio.h>
#include <mach-o/dyld.h>

#include "libmeow.h"

void offsetfinder64_kread(void);
static unsigned char header[0x4000];
typedef unsigned long long addr_t;
int InitPatchfinder(addr_t, const char*);
addr_t Find_trustcache(void);
#endif /* meowfinder_h */
