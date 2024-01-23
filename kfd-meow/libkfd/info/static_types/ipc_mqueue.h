//
//  ipc_mqueue.h
//  Telescope
//
//  Created by Jonah Butler on 1/22/24.
//

#ifndef ipc_mqueue_h
#define ipc_mqueue_h
#include "waitq.h"
struct klist;
struct ipc_mqueue {
    union {
        struct {
            struct waitq waitq;
            struct {
                void *ikmq_base;
            }  messages;
            mach_port_seqno_t seqno;
            mach_port_name_t receiver_name;
            uint16_t msgcount;
            uint16_t qlimit;
        } port;
        struct {
            struct {
                struct waitq wqset_q;
                uint64_t wqset_id;
                union {
                    uint64_t wqset_prepost_id;
                    void *wqset_prepost_hook;
                };
            } setq;
        } pset;
    } data;
    union {
        struct klist imq_klist;
        void *imq_inheritor_knote;
        void *imq_inheritor_turnstile;
        thread_t imq_inheritor_thread_ref;
        thread_t imq_srp_owner_thread;
    };
};
#endif /* ipc_mqueue_h */
