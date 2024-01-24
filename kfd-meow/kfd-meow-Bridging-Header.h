//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <Foundation/Foundation.h>
#include "libgrabkernel.h"
#include "libkfd.h"
#include "libmeow.h"
#include "pplrw.h"
#include "overwrite/overwrite.h"
#include "loadtelescoped.h"
#include "posix_spawn.h"
#include <mach/arm/thread_status.h>

extern uint64_t _kfd;

extern uint64_t kpoen_bridge(uint64_t puaf_method, uint64_t pplrw);

extern uint64_t meow_and_kclose(uint64_t _kfd);