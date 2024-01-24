//
//  server.h
//  Telescope
//
//  Created by Jonah Butler on 1/23/24.
//

#ifndef server_h
#define server_h
typedef enum {
    JUPITER_MSG_TELESCOPE_EXCLUSIVE_READYFORKOPEN = 1,
    JUPITER_MSG_KREAD64 = 2,
    JUPITER_MSG_KWRITE64 = 3,
    JUPITER_MSG_PPLWRITEVIRT64 = 4,
    JUPITER_MSG_ADD_TRUSTCACHE = 5,
    JUPITER_MSG_INIT_ENVIRONMENT = 6,
    JUPITER_MSG_SET_PID_DEBUGGED = 7,
    JUPITER_MSG_SET_PID_PLATFORMIZED = 8,
} JUPITER_MESSAGE_NAME;
#endif /* server_h */
