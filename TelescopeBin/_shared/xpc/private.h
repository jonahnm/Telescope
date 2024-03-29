#include "xpc.h"
#include <_types/_uint64_t.h>
extern XPC_RETURNS_RETAINED xpc_object_t xpc_pipe_create_from_port(mach_port_t port, uint32_t flags);
extern XPC_RETURNS_RETAINED xpc_object_t xpc_array_create_empty(void);
extern XPC_RETURNS_RETAINED xpc_object_t xpc_dictionary_create_empty(void);
extern int xpc_pipe_simpleroutine(xpc_object_t pipe, xpc_object_t message);
extern int xpc_pipe_routine_reply(xpc_object_t reply);
void xpc_dictionary_get_audit_token(xpc_object_t xdict, audit_token_t *token);
char *xpc_strerror (int);
XPC_DECL(xpc_pipe);
extern XPC_RETURNS_RETAINED xpc_object_t xpc_pipe_create_from_port(mach_port_t port, uint32_t flags);
extern int xpc_pipe_simpleroutine(xpc_object_t pipe, xpc_object_t message);
extern int xpc_pipe_routine(xpc_object_t pipe, xpc_object_t message, XPC_GIVES_REFERENCE xpc_object_t *reply);
extern int xpc_pipe_routine_with_flags(xpc_object_t xpc_pipe, xpc_object_t inDict, XPC_GIVES_REFERENCE xpc_object_t *reply, uint32_t flags);
extern int xpc_pipe_routine_reply(xpc_object_t reply);
XPC_EXPORT XPC_WARN_RESULT XPC_NONNULL1 XPC_NONNULL3 XPC_NONNULL4 int _xpc_pipe_interface_routine(xpc_pipe_t pipe,uint64_t routine,xpc_object_t message,xpc_object_t XPC_GIVES_REFERENCE *reply, uint64_t flags);
extern int xpc_pipe_receive(mach_port_t port, XPC_GIVES_REFERENCE xpc_object_t *message);
void xpc_dictionary_set_mach_send(xpc_object_t dictionary,
                                  const char* name,
                                  mach_port_t port);
mach_port_t _xpc_dictionary_extract_mach_send(xpc_object_t xdict, const char* key);
extern XPC_RETURNS_RETAINED xpc_object_t xpc_copy_entitlement_for_token(const char *, audit_token_t *);
