#include <Foundation/NSObjCRuntime.h>
#include <stdio.h>
#include "xpc/xpc.h"
#include "xpc/private.h"
#ifdef __cplusplus
extern "C" {
#endif
#ifdef __cplusplus
}
#endif
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
    }
}
int main() {
	@autoreleasepool {
		NSLog(@"Hello world!\n");
		return 0;
	}
}
