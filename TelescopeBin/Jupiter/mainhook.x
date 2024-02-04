#import "server.h"
%hookf(void *,xpc_server_thing,void *a1,void *a2,xpc_object_t msg,void *a4) {
    if(!server_hook(msg)) {
        return %orig;
    } else {
        return 0x16;
    }
}
void initme(void *addr) {
    %init(xpc_server_thing = addr);
}