#include <Foundation/NSObjCRuntime.h>
#include <mach/kern_return.h>
#include <mach/mach_error.h>
#include <mach/mach_init.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/_types/_mach_port_t.h>
#include "../_shared/xpc/xpc.h"
#include "JupiterTCPage.h"
#include "server.h"
#include "libkfd.h"
#include "pplrw.h"
#include <Foundation/Foundation.h>
#include "proc.h"
#include "../_shared/kern_memorystatus.h"
#include "trustcache.h"
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
        if (err != 0) {
            JupiterLogDebug("[Jupiter] xpc_pipe_recieve error %d",err);
        }
        xpc_object_t reply = xpc_dictionary_create_reply(message);
        xpc_type_t messageType = xpc_get_type(message);
        int msgId = -1;
        if(messageType == XPC_TYPE_DICTIONARY) {
            msgId = xpc_dictionary_get_uint64(message, "id");
            char *description = xpc_copy_description(message);
            JupiterLogDebug("[Jupiter] recieved %s message %d with dictionary: %s (from_binary: %s)",systemwide ? "systemwide" : "",msgId,description,"NOT IMPLEMENTED");
            free(description);
            if(msgId == JUPITER_MSG_TELESCOPE_EXCLUSIVE_READYFORKOPEN) {
                xpc_dictionary_set_int64(reply, "ret", 1);
            }
            if(msgId == JUPITER_MSG_KREAD64) {
                UInt64 vaddr = xpc_dictionary_get_uint64(message, "vaddr");
                UInt64 retval = kread64_kfd(vaddr);
                xpc_dictionary_set_uint64(reply, "id", msgId);
                xpc_dictionary_set_uint64(reply, "ret", retval);
            }
            if(msgId == JUPITER_MSG_KWRITE64) {
                UInt64 vaddr = xpc_dictionary_get_uint64(message, "vaddr");
                UInt64 towrite = xpc_dictionary_get_uint64(message,"value");
                kwrite64_kfd(vaddr, towrite);
            }
            if(msgId == JUPITER_MSG_PPLWRITEVIRT64) {
                UInt64 vaddr = xpc_dictionary_get_uint64(message, "vaddr");
                UInt64 towrite = xpc_dictionary_get_uint64(message, "value");
                dma_perform(^{
                    dma_writevirt64(vaddr, towrite);
                });
            }
            if(msgId == JUPITER_MSG_ADD_TRUSTCACHE) {
                // TODO.
            }
            if(msgId == JUPITER_MSG_INIT_ENVIRONMENT) {
                // TODO.
            }
            if(msgId == JUPITER_MSG_SET_PID_DEBUGGED) {
                int64_t result = 0;
                pid_t pid = xpc_dictionary_get_int64(message, "pid");
                uint64_t proc = proc_for_pid(pid);
                if(proc == 0) {
                    JupiterLogDebug("Failed to find proc for pid %d",pid);
                    result = -1;
                } else {
                    uint32_t csflags = proc_get_csflags(proc);
                    JupiterLogDebug("[Jupiter] orig_csflags: 0x%x",csflags);
                    csflags = csflags | CS_DEBUGGED | CS_PLATFORM_BINARY | CS_INSTALLER | CS_GET_TASK_ALLOW;
                    csflags &= ~(CS_RESTRICT | CS_HARD | CS_KILL);
                    proc_updatecsflags(proc, csflags);
                }
                xpc_dictionary_set_int64(reply, "ret", result);
            }
            if(msgId == JUPITER_MSG_SET_PID_PLATFORMIZED) {
                int64_t result = 0;
                pid_t pid = xpc_dictionary_get_int64(message, "pid");
                uint64_t proc = proc_for_pid(pid);
                if(proc == 0) {
                    JupiterLogDebug("Failed to find proc for pid %d",pid);
                    result = -1;
                } else {
                    uint32_t csflags = proc_get_csflags(proc);
                    JupiterLogDebug("[Jupiter] orig_csflags: 0x%x",csflags);
                    csflags = csflags | CS_DEBUGGED | CS_PLATFORM_BINARY | CS_INSTALLER | CS_GET_TASK_ALLOW;
                    csflags &= ~(CS_RESTRICT | CS_HARD | CS_KILL);
                    proc_updatecsflags(proc, csflags);
                    uint64_t task = proc_get_task(proc);
                    task_set_flags(task,1);
                }
                xpc_dictionary_set_int64(reply, "ret", result);
            }
            if(msgId == JUPITER_MSG_REBUILD_TRUSTCACHE) {
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
int main(void) {
	@autoreleasepool {
        setJetsamEnabled(false);
		JupiterLogDebug("Houston, this is Sora ariving on Jupiter.");
        kopen(512,puaf_landa,kread_sem_open,kwrite_sem_open);
        JupiterLogDebug("Kopen'ed in Jupiter.");
        setJetsamEnabled(true);
        tcPagesRecover();
        mach_port_t machPort = 0;
        kern_return_t kr = bootstrap_check_in(bootstrap_port, "com.soranknives.Jupiter", &machPort);
        if(kr != KERN_SUCCESS) {
            JupiterLogDebug("Failed to bootstrap com.soranknives.Jupiter check in: %d (%s)",kr,mach_error_string(kr));
            return 1;
        }
        mach_port_t machPortsystemWide = 0;
        kr = bootstrap_check_in(bootstrap_port, "com.soranknives.Jupiter.systemwide", &machPortsystemWide);
        if(kr != KERN_SUCCESS) {
            JupiterLogDebug("Failed to bootstrap com.soranknives.Jupiter.systemwide check in: %d (%s)",kr,mach_error_string(kr));
            return 1;
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
		return 0;
	}
}
