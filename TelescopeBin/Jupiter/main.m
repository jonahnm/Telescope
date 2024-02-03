#include <Foundation/NSObjCRuntime.h>
#include <mach/kern_return.h>
#include <mach/mach_error.h>
#include <mach/mach_init.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/_types/_mach_port_t.h>
#include <IOSurface/IOSurfaceRef.h>
#include "../_shared/xpc/xpc.h"
#include "JupiterTCPage.h"
#include "server.h"
#include "fun/krw.h"
#include "fun/ppl/pplrw.h"
#include <Foundation/Foundation.h>
#include <unistd.h>
#include "../_shared/xpc/xpc.h"
#include "../_shared/xpc/private.h"
#include "proc.h"
#include "../_shared/kern_memorystatus.h"
#include "trustcache.h"
#include "boot_info.h"
#include "fun/krw.h"
#ifdef __cplusplus
extern "C" {
#endif
uid_t audit_token_to_pid(audit_token_t);
kern_return_t bootstrap_check_in(mach_port_t bootstrap_port,const char *service,mach_port_t *server_port);
#ifdef __cplusplus
}
#endif
void setJetsamEnabled(bool enabled) {
    pid_t me = getpid();
    int priorityToSet = -1;
    if(enabled) {
        priorityToSet = 500;
    }
    int rc = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK,me,priorityToSet,NULL,0);
    if (rc < 0) {
        perror("memorystatus_control");
    }
}
void JupiterLogDebug(const char* format,...) {
    va_list va;
    va_start(va, format);
    char buf[0x1000];
    FILE *jupiter_log = fopen("/var/mobile/jupiter-xpc.log","a");
    if(jupiter_log) {
        vfprintf(jupiter_log, format, va);
        fprintf(jupiter_log,"\n");
        fclose(jupiter_log);
    }
    vsnprintf(buf, sizeof(buf), format,va);
    NSLog(@"%s",buf);
    va_end(va);
}
void jupiter_recieved_message(mach_port_t machPort,bool systemwide) {
    @autoreleasepool {
        xpc_object_t message = nil;
        int err = xpc_pipe_receive(machPort, &message);
        xpc_object_t reply = xpc_dictionary_create_reply(message);
        xpc_type_t messageType = xpc_get_type(message);
        int msgId = -1;
        if(messageType == XPC_TYPE_DICTIONARY) {
            msgId = xpc_dictionary_get_uint64(message, "id");
            char *description = xpc_copy_description(message);
            JupiterLogDebug("[Jupiter] recieved %s message %d with dictionary: %s (from_binary: %s)",systemwide ? "systemwide" : "",msgId,description,"NOT IMPLEMENTED");
            free(description);
            if(msgId == JUPITER_MSG_POLL_IS_READY) {
                xpc_dictionary_set_int64(reply, "ret", 1);
            }
            if(msgId == JUPITER_MSG_KREAD64) {
                UInt64 vaddr = xpc_dictionary_get_uint64(message, "vaddr");
                UInt64 retval = kread64(vaddr);
                xpc_dictionary_set_uint64(reply, "id", msgId);
                xpc_dictionary_set_uint64(reply, "ret", retval);
            }
            if(msgId == JUPITER_MSG_KWRITE64) {
                UInt64 vaddr = xpc_dictionary_get_uint64(message, "vaddr");
                UInt64 towrite = xpc_dictionary_get_uint64(message,"value");
                kwrite64(vaddr, towrite);
            }
            if(msgId == JUPITER_MSG_PPLWRITEVIRT64) {
                UInt64 vaddr = xpc_dictionary_get_uint64(message, "vaddr");
                UInt64 towrite = xpc_dictionary_get_uint64(message, "value");
                dma_perform(^{
                    dma_writevirt64(vaddr, towrite);
                });
                xpc_dictionary_set_int64(reply, "ret", 1);
            }
            if(msgId == JUPITER_MSG_ADD_TRUSTCACHE) {
                __block JupiterTCPage *mappedInPage = nil;
                const char *path = xpc_dictionary_get_string(message, "path");
                if(path) {
                    NSString *NSpath = [NSString stringWithCString:path encoding:NSUTF8StringEncoding];
                    NSURL *URL = [NSURL fileURLWithPath:NSpath];
                    fileEnumerateTrustCacheEntries(URL, ^(trustcache_entry entry) {
                        if(!mappedInPage || mappedInPage.amountOfSlotsLeft == 0) {
                        if(mappedInPage) {
                            [mappedInPage sort];
                        }
                        mappedInPage = trustCacheFindFreePage();
                    }
                    trustcache_entry2 entry2;
                    memcpy(&entry2.hash,entry.hash,CS_CDHASH_LEN);
                    entry2.hash_type =  entry.hash_type;
                    entry2.flags = entry.flags;
                    [mappedInPage addEntry2:entry2];
                    });
                }
            }
            if(msgId == JUPITER_MSG_INIT_ENVIRONMENT) {
                // TODO.
            }
            if(msgId == JUPITER_MSG_SET_PID_DEBUGGED) {
                // TODO.
            }
            if(msgId == JUPITER_MSG_SET_PID_PLATFORMIZED) {
                // TODO.
            }
            if(msgId == JUPITER_MSG_REBUILD_TRUSTCACHE) {
                tcPagesRecover();
                rebuildDynamicTrustCache();
                xpc_dictionary_set_int64(reply, "ret", 1);
            }
            if(reply) {
                err = xpc_pipe_routine_reply(reply);
                if(err != 0) {
                    JupiterLogDebug("[Jupiter] Error %d sending response",err);
                }
            }
        }
    }
}
__attribute__((constructor)) static void initializer(void)
{
	@autoreleasepool {
		JupiterLogDebug("Houston, this is Sora ariving on Launchd's Jupiter.");
        sleep(1);
        do_kopen(512, 2, 1, 1);
        JupiterLogDebug("Launchd's Jupiter kopened!");
        mach_port_t machPort = 0;
        kern_return_t kr = bootstrap_check_in(bootstrap_port, "com.soranknives.Jupiter", &machPort);
        if(kr != KERN_SUCCESS) {
            JupiterLogDebug("Failed to bootstrap com.soranknives.Jupiter check in: %d (%s)",kr,mach_error_string(kr));
            return;
        }
        mach_port_t machPortsystemWide = 0;
        kr = bootstrap_check_in(bootstrap_port, "com.soranknives.Jupiter.systemwide", &machPortsystemWide);
        if(kr != KERN_SUCCESS) {
            JupiterLogDebug("Failed to bootstrap com.soranknives.Jupiter.systemwide check in: %d (%s)",kr,mach_error_string(kr));
            return;
        }
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)machPort, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{
            mach_port_t lMachPort = (mach_port_t)dispatch_source_get_handle(source);
            jupiter_recieved_message(lMachPort, false);
        });
        dispatch_resume(source);
        dispatch_source_t sourceSsystemWide = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)machPortsystemWide, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sourceSsystemWide, ^{
            mach_port_t lMachPort = (mach_port_t)dispatch_source_get_handle(sourceSsystemWide);
            jupiter_recieved_message(lMachPort, true);
        });
        dispatch_resume(sourceSsystemWide);
        dispatch_main();
	}
}
