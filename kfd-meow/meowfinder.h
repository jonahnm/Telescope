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
static unsigned char header[0x4000];
#include "libmeow.h"

void offsetfinder64_kread(void);

#endif /* meowfinder_h */
