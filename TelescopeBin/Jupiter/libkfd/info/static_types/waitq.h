//
//  waitq.h
//  Telescope
//
//  Created by Jonah Butler on 1/22/24.
//

#ifndef waitq_h
#define waitq_h
#define _EVENT_MASK_BITS   ((sizeof(uint32_t) * 8) - 7)
struct waitq {
    uint32_t /* flags */
            waitq_type:2,        /* only public field */
            waitq_fifo:1,        /* fifo wakeup policy? */
            waitq_prepost:1,     /* waitq supports prepost? */
            waitq_irq:1,         /* waitq requires interrupts disabled */
            waitq_isvalid:1,     /* waitq structure is valid */
            waitq_turnstile:1,   /* waitq is embedded in a turnstile */
            waitq_eventmask:_EVENT_MASK_BITS;
    uint32_t waitq_interlock;
    uint64_t waitq_set_id;
    uint64_t waitq_prepost_id;
    union {
        struct {
            void *ptr1;
            void *ptr2;
        } waitq_queue;
        struct {
            void *ptr;
        } waitq_prio_queue;
        struct {
            void *waitq_ts;
            union {
                void *waitq_tspriv;
                int waitq_priv_pid;
            };
        };
    };
};

#endif /* waitq_h */
