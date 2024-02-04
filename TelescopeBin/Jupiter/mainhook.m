#include <Foundation/NSObjCRuntime.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/kern_return.h>
#include <mach/mach_error.h>
#include <mach/mach_init.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
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
#include <mach-o/getsect.h>
#import <Jupiter-Swift.h>
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
        priorityToSet = 150;
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
/*
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
*/
bool server_hook(xpc_object_t msg) {
    JupiterLogDebug("Hook called!");
    xpc_type_t msgtype = xpc_get_type(msg);
    if(msgtype == XPC_TYPE_DICTIONARY) {
        if(!xpc_dictionary_get_bool(msg, "JAILBREAK")) {
            return false;
        }
        xpc_object_t reply = xpc_dictionary_create_reply(msg);
        uint64_t id = xpc_dictionary_get_uint64(msg, "id");
        if(id == JUPITER_MSG_POLL_IS_READY) {
            xpc_dictionary_set_int64(reply, "ret", 1);
        }
        if(id == JUPITER_MSG_KOPEN) {
            do_kopen(512, 2, 1, 1);
            xpc_dictionary_set_int64(reply, "ret",1);
        }
        if(reply) {
            int err = xpc_pipe_routine_reply(reply);
            if(err != 0) {
                JupiterLogDebug("Failed to send response!");
            }
        }
        return true;
    }
    return false;
}
__attribute__((constructor)) static void initializer(void)
{
	void *addr = [patchfinder find_server]; // Ignore any errors here, it's just clangd being annoying.
    if((uint64_t)addr < 5) {
        switch((uint64_t)addr) {
            case 0:
                JupiterLogDebug("Patchfinding failed because I failed to open the Mach-O file.");
                break;
            case 1:
                JupiterLogDebug("Patchfinding failed because I couldn't find the __TEXT__text section.");
                break;
            case 2:
                JupiterLogDebug("Patchfinding failed because I couldn't find the __TEXT__cstring section.");
                break;
            case 3:
                JupiterLogDebug("Patchfinding failed because I couldn't find the 'path' string.");
                break;
            case 4:
                JupiterLogDebug("Patchfinding failed because I failed to find an XRef to the 'path' string.");
                break;
        }
        sleep(2);
        return; // Will cause a panic if I continue.
    }
    const struct segment_command_64 *command = getsegbyname("__TEXT");
    uint64_t staticbaseaddr = command->vmaddr;
    uint64_t slide = 0;
    for(uint32_t i = 0; i < _dyld_image_count(); i++) {
        if(strcmp(_dyld_get_image_name(i), "/sbin/launchd") == 0) {
                slide = _dyld_get_image_vmaddr_slide(i);
                break;
        }
    }
    uint64_t actualbaseaddr = staticbaseaddr + slide;
    JupiterLogDebug("Hooking address: %p",addr);
    sleep(1);
    void *slidaddr = addr + actualbaseaddr;
    JupiterLogDebug("Slid hooking address: %p",slidaddr);
    sleep(1);
    initme(slidaddr);
}
