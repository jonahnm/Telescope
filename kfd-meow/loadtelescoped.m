//
//  loadtelescoped.m
//  Telescope
//
//  Created by Jonah Butler on 1/15/24.
//

#include "libkfd.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "loadtelescoped.h"
#import "pplrw.h"
#import "IOSurface_Primitives.h"
#import "libkfd/perf.h"
#define SYSTEM_VERSION_LOWER_THAN(v)                ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)
#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

extern int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr); // this gives me the heebeejeebees (or however the fuck you spell it)
extern int userspaceReboot(void);

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
UInt64 load_telescope(void)
{
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
    spawnRoot(helper, @[@"copy", @"/usr/libexec/amfid", @(originalamfid)], &out, &err);
    spawnRoot(helper, @[@"copy", @"/usr/libexec/xpcproxy", @(originalxpc)], &out, &err);

    spawnRoot(helper, @[@"xmldump", @"/usr/libexec/amfid", [@(originalamfid) stringByAppendingPathExtension:@"plist"]], &out, &err);
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
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &exceptionPort);
    mach_port_insert_right(mach_task_self(), exceptionPort, exceptionPort, MACH_MSG_TYPE_MAKE_SEND);
    task_set_exception_ports(amfidport, EXC_MASK_BAD_ACCESS, exceptionPort, EXCEPTION_DEFAULT,6);
    vm_address_t page = (loadAddress + offset_MISIAblalbdl) & ~vm_page_mask;
    vm_protect(amfidport, page, vm_page_size, 0, VM_PROT_READ | VM_PROT_WRITE);
    UInt64 data = ptrauth_sign_unauthenticated((void*)0x12345, ptrauth_key_asia, (loadAddress + offset_MISIAblalbdl));
    vm_write(amfidport,(loadAddress + offset_MISIAblalbdl),&data,sizeof(UInt64)); //Nobody likes you, amfid.
    NSLog(@"Amfid should now crash as soon as it tries to authenticate a binary, we will redirect handle this exception to make it continue, and allow the unauthenticated binary.");ßßß
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
    return 0;
}
