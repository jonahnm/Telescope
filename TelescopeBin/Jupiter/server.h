//
//  server.h
//  Telescope
//
//  Created by Jonah Butler on 1/23/24.
//

#ifndef server_h
#define server_h
#include "../_shared/xpc/xpc.h"
typedef enum {
    JUPITER_MSG_POLL_IS_READY = 1,
    JUPITER_MSG_KREAD64 = 2,
    JUPITER_MSG_KWRITE64 = 3,
    JUPITER_MSG_PPLWRITEVIRT64 = 4,
    JUPITER_MSG_ADD_TRUSTCACHE = 5,
    JUPITER_MSG_INIT_ENVIRONMENT = 6,
    JUPITER_MSG_SET_PID_DEBUGGED = 7,
    JUPITER_MSG_SET_PID_PLATFORMIZED = 8,
    JUPITER_MSG_REBUILD_TRUSTCACHE = 9,
    JUPITER_MSG_TELESCOPE_EXCLUSIVE_HANDOFF = 10,
    JUPITER_MSG_KOPEN = 11,
    JUPITER_MSG_PASS_PIPE = 12,
} JUPITER_MESSAGE_NAME;
bool server_hook(xpc_object_t msg);
void initme(void *addr);
#endif /* server_h */
