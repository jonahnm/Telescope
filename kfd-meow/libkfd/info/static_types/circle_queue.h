//
//  circle_queue.h
//  Telescope
//
//  Created by Jonah Butler on 1/22/24.
//

#ifndef circle_queue_h
#define circle_queue_h
typedef struct circle_queue_head {
    struct {
        void *next;
        void *prev;
    } head;
} circle_queue_head_t, *circle_queue_t;

#endif /* circle_queue_h */
