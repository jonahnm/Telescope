// fork() and rootless fix for Procursus bootstrap (named libTS2JailbreakEnv.dylib)
// there's lots of stuff not cleaned up, feel free to play around
// Requires fishhook from https://github.com/khanhduytran0/fishhook
// Usage: inject to libiosexec.dylib, ensure all binaries have get-task-allow entitlement

// https://gist.githubusercontent.com/khanhduytran0/675bba3db59bb7fac3ceaa49f2ef24e1/raw/861f719fe22a5ade09f5be22610b2f4264343a39/ProcursusTSHelper.c

#include <limits.h>
#include <assert.h>
#include <errno.h>
#include <mach/mach_init.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include "fishhook.h"

#include <signal.h>
#include <unistd.h>
#include <execinfo.h>
#include <stdlib.h>

#define printf(...) // __VA_ARGS__

const char* mach_error_string(kern_return_t);
kern_return_t mach_vm_allocate(vm_map_t          target_task,                  mach_vm_address_t address,                  mach_vm_size_t    size,                  int               flags);
kern_return_t mach_vm_map(vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t size, mach_vm_offset_t mask, int flags, mem_entry_name_port_t object, memory_object_offset_t offset, boolean_t copy, vm_prot_t cur_protection, vm_prot_t max_protection, vm_inherit_t inheritance);
kern_return_t mach_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_max, vm_prot_t new_prot);
kern_return_t mach_vm_copy(vm_map_t          target_task,              mach_vm_address_t source_address,              mach_vm_size_t    count,              mach_vm_address_t dest_address);

#define PT_TRACE_ME     0
#define PT_DETACH       11
#define PT_ATTACHEXC    14
int ptrace(int, pid_t, caddr_t, int);

static uint64_t THE_OFFSET;

int (*orig_fork)(void);
int (*orig_vfork)(void);
int (*orig_access)(const char *path, int amode);
int (*orig_execve)(const char* path, char* const argv[], char* const envp[]);
int (*orig_posix_spawn)(pid_t *restrict pid, const char *restrict path,
  const posix_spawn_file_actions_t *file_actions,
  const posix_spawnattr_t *restrict attrp, char *const argv[restrict],
  char *const envp[restrict]);
int (*orig_stat)(const char *restrict path, struct stat *restrict buf);

void handleFaultyTextPage(int signum, struct siginfo_t* siginfo, void* context)
{
    static int failureCount;

    printf("Got SIGBUS, fixing\n");

    struct __darwin_ucontext* ucontext = (struct __darwin_ucontext*) context;
    struct __darwin_mcontext64* machineContext = ucontext->uc_mcontext;
    
    uint64_t programCounter = machineContext->__ss.__pc;
    machineContext->__ss.__pc += THE_OFFSET;
    if (*(uint64_t *)programCounter != *(uint64_t *)machineContext->__ss.__pc) {
        fprintf(stderr, "pc and pc+off instruction doesn't match\n");
        kill(getpid(), SIGKILL);
    }
    printf("jump: %p -> %p\n", programCounter, machineContext->__ss.__pc);
}

#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
int isJITEnabled() {
    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
}

const struct segment_command_64 *builtin_getsegbyname(struct mach_header_64 *mhp, char *segname)
{
    struct segment_command_64 *sgp;
    uint32_t i;
        
    sgp = (struct segment_command_64 *)
	      ((char *)mhp + sizeof(struct mach_header_64));
    for (i = 0; i < mhp->ncmds; i++){
        if(sgp->cmd == LC_SEGMENT_64)
            if(strncmp(sgp->segname, segname, sizeof(sgp->segname)) == 0)
                return(sgp);
            sgp = (struct segment_command_64 *)((char *)sgp + sgp->cmdsize);
    }
    return NULL;
}

size_t size_of_image(struct mach_header_64 *header) {
    struct load_command *lc = (struct load_command *) (header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        //printf("cmd %d = %d\n", i, lc->cmd);
        if (lc->cmd == LC_CODE_SIGNATURE) {
            struct linkedit_data_command *cmd = (struct linkedit_data_command *)lc;
            //printf("size %d\n", cmd->dataoff + cmd->datasize);
            return header->sizeofcmds + cmd->dataoff + cmd->datasize;
        }
        lc = (struct load_command *) ((char *) lc + lc->cmdsize);
    }
    printf("LC_CODE_SIGNATURE is not found\n");
    abort();
    return 0;
}

static void post_fork(int pid) {
    printf("fork pid=%d\n", pid);
    if (pid == 0) {
        // fix fork by any chance...
        kill(getpid(), SIGSTOP);
        usleep(2000);

        if (THE_OFFSET) return;

        kern_return_t result;
        const struct mach_header_64 *header = _dyld_get_image_header(0);
        uint64_t slide = _dyld_get_image_vmaddr_slide(0);
        size_t size = size_of_image(header);

        // SIMULATE READ ONLY
        //const struct section_64 *thisSect = getsectbyname(SEG_TEXT, SECT_TEXT);
        //result = mach_vm_protect(mach_task_self(), thisSect->addr + slide, thisSect->size, TRUE, VM_PROT_READ);
        //printf("RO mach_vm_protect: %s\n", mach_error_string(result));

        // Copy the whole image memory
        //mach_vm_address_t remap;
        const struct mach_header_64 *remap;
        result = mach_vm_map(mach_task_self(), &remap, size, 0, VM_FLAGS_ANYWHERE, NULL, NULL, FALSE, VM_PROT_READ|VM_PROT_WRITE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE, VM_INHERIT_DEFAULT);
        printf("line %d: %p\n", __LINE__, remap);
        result = mach_vm_copy(mach_task_self(), header, size, remap);
        printf("line %d: %s\n", __LINE__, mach_error_string(result));
        THE_OFFSET = (uint64_t)remap - (uint64_t)header;
        printf("offset=%p\n", THE_OFFSET);

        const struct segment_command_64 *seg = builtin_getsegbyname(remap, SEG_TEXT);
        mach_vm_address_t text_remap = remap + (seg->vmaddr + slide - (uint64_t)header);
        result = mach_vm_protect(mach_task_self(), text_remap, seg->vmsize, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        printf("mach_vm_protect(%p): %s\n", text_remap, mach_error_string(result));

        // Unblock signal handler
        sigset_t set;
        sigemptyset(&set);
        sigprocmask(SIG_SETMASK, &set, 0);

        struct sigaction sigAction;
        sigAction.sa_sigaction = handleFaultyTextPage;
        sigAction.sa_flags = SA_SIGINFO;
        sigaction(SIGBUS, &sigAction, NULL);

        if (!isJITEnabled()) {
            fprintf(stderr, "forked process couldn't get JIT, killing\n");
            kill(getpid(), SIGKILL);
        }
    } else if (pid > 0) {
        // Enable JIT for the child process
        int ret;
        ret = ptrace(PT_ATTACHEXC, pid, 0, 0);
        if (!ret && !isJITEnabled()) {
            fprintf(stderr, "%s: looks like this process does not have get-task-allow entitlement. Forkfix will abort\n", getprogname());
            abort();
        }
        kill(pid, SIGCONT);
        if (!ret) {
            // Detach process
            for (int i = 0; i < 1000; i++) {
                usleep(1000);
                ret = ptrace(PT_DETACH, pid, 0, 0);
                if (!ret) break;
            }
            printf("detach=%d\n", ret);
        }
        //assert(!ret);
    }
}

int hooked_fork() {
    int pid = orig_fork();
    post_fork(pid);
    return pid;
}

int hooked_vfork() {
    int pid = orig_vfork();
    post_fork(pid);
    return pid;
}

static void fix_bin_path(const char* path, char* newPath) {
    uint16_t len = strlen(path);
    if (len > 5 && !strncmp(path, "/bin/", 5) && orig_access(path, F_OK) != 0) {
        errno = 0;
        sprintf(newPath, "/var/jb%s", path);
        //fprintf(stderr, "%s -> %s\n", path, newPath);
    } else {
        sprintf(newPath, "%s", path);
    }
}

int hooked_access(const char *path, int amode) {
    char newPath[PATH_MAX];
    fix_bin_path(path, newPath);
    return orig_access(newPath, amode);
}

int hooked_execve(const char* path, char* const argv[], char* const envp[]) {
    char newPath[PATH_MAX];
    fix_bin_path(path, newPath);
    return orig_execve(newPath, argv, envp);
}

int hooked_posix_spawn(pid_t *restrict pid, const char *restrict path,
  const posix_spawn_file_actions_t *file_actions,
  const posix_spawnattr_t *restrict attrp, char *const argv[restrict],
  char *const envp[restrict]) {
    char newPath[PATH_MAX];
    fix_bin_path(path, newPath);
    return orig_posix_spawn(pid, newPath, file_actions, attrp, argv, envp);
}

int hooked_stat(const char *restrict path, struct stat *restrict buf) {
    char newPath[PATH_MAX];
    fix_bin_path(path, newPath);
    return orig_stat(newPath, buf);
}

__attribute__((constructor)) static void init(int argc, char **argv) {
    setenv("DYLD_INSERT_LIBRARIES", "", 0);
    setenv("JB_ROOT_PATH", "/var/jb", 0);
    setenv("JB_SANDBOX_EXTENSIONS", "", 0);

    char *current_path = getenv("PATH");
    char new_path[PATH_MAX];
    snprintf(new_path, sizeof(new_path), "%s:/var/jb:/var/jb/bin", current_path);
    setenv("PATH", new_path, 1);

    struct rebinding rebindings[] = (struct rebinding[]){
        // fork() fix
        {"fork", hooked_fork, (void *)&orig_fork},
        {"vfork", hooked_vfork, (void *)&orig_vfork},
        // shell fix for git, make and tar
        {"execve", hooked_execve, (void *)&orig_execve},
        // shell fix for make
        {"access", hooked_access, (void *)&orig_access},
        {"posix_spawn", hooked_posix_spawn, (void *)&orig_posix_spawn},
        {"stat", hooked_stat, (void *)&orig_stat},
    };
    rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
}