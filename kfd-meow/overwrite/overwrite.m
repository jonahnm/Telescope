#include "./overwrite.h"

#ifndef HEXDUMP_COLS
#define HEXDUMP_COLS 16
#endif

void hexdump(void *mem, unsigned int len) {
        unsigned int i, j;
        for(i = 0; i < len + ((len % HEXDUMP_COLS) ? (HEXDUMP_COLS - len % HEXDUMP_COLS) : 0); i++)
        {
                /* print offset */
                if(i % HEXDUMP_COLS == 0)
                {
                        printf("0x%06x: ", i);
                }
 
                /* print hex data */
                if(i < len)
                {
                        printf("%02x ", 0xFF & ((char*)mem)[i]);
                }
                else /* end of block, just aligning for ASCII dump */
                {
                        printf("   ");
                }
                
                /* print ASCII dump */
                if(i % HEXDUMP_COLS == (HEXDUMP_COLS - 1))
                {
                        for(j = i - (HEXDUMP_COLS - 1); j <= i; j++)
                        {
                                if(j >= len) /* end of block, not really printing */
                                {
                                        putchar(' ');
                                }
                                else if(isprint(((char*)mem)[j])) /* printable char */
                                {
                                        putchar(0xFF & ((char*)mem)[j]);
                                }
                                else /* other char */
                                {
                                        putchar('.');
                                }
                        }
                        putchar('\n');
                }
        }
}

void kreadump_kfd(uint64_t where, unsigned int len) {
    int *buf = malloc(sizeof(int) * len);
      for (int i = 0; i < len; i++) {
          buf[i] = 0;
      }
    kreadbuf_kfd(where, buf, len);
    hexdump(buf, len);
    free(buf);
}

uint64_t getVnodeAtPath(char* filename) {
    int file_index = open(filename, O_RDONLY);
    if (file_index == -1) return -1;
    
    uint64_t proc = get_current_proc();

    uint64_t filedesc_pac = kread64_kfd(proc + off_proc_pfd);
    uint64_t filedesc = filedesc_pac | 0xffffff8000000000;
    uint64_t openedfile = kread64_kfd(filedesc + (8 * file_index));
    uint64_t fileglob_pac = kread64_kfd(openedfile + off_fp_glob);
    uint64_t fileglob = fileglob_pac | 0xffffff8000000000;
    uint64_t vnode_pac = kread64_kfd(fileglob + off_fg_data);
    uint64_t vnode = vnode_pac | 0xffffff8000000000;
    
    close(file_index);
    
    return vnode;
}

uint64_t getVnodeAtPathByChdir(char *path) {
    printf("[+] getVnodeAtPathByChdir(%s)\n", path);
    if(access(path, F_OK) == -1) {
        printf("access not OK\n");
        return -1;
    }
    if(chdir(path) == -1) {
        printf("chdir not OK\n");
        return -1;
    }
    uint64_t fd_cdir_vp = kread64_kfd(get_current_proc() + off_proc_pfd + off_fd_cdir);
    chdir("/");
    printf("[+] fd_cdir_vp: 0x%llx\n", fd_cdir_vp);
    return fd_cdir_vp;
}

uint64_t findChildVnodeByVnode(uint64_t vnode, char* childname) {
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
        
        char vp_name[sizeof(uint64_t)];
        kreadbuf_kfd(vp_nameptr, &vp_name, sizeof(uint64_t) + sizeof(uint64_t));
        
        if(strcmp(vp_name, childname) == 0) {
            kreadump_kfd(vp_nameptr, sizeof(uint64_t) + sizeof(uint64_t));
            return vnode;
        }
        vp_namecache = kread64_kfd(vp_namecache + off_namecache_nc_child_tqe_prev);
    }

    return 0;
}


uint64_t funVnodeRedirectFile(char* to, char* from, uint64_t* orig_to_vnode, uint64_t* orig_nc_vp)
{
    uint64_t to_vnode = getVnodeAtPath(to);
    if(to_vnode == -1) {
        NSString *to_dir = [[NSString stringWithUTF8String:to] stringByDeletingLastPathComponent];
        NSString *to_file = [[NSString stringWithUTF8String:to] lastPathComponent];
        uint64_t to_dir_vnode = getVnodeAtPathByChdir(to_dir.UTF8String);
        to_vnode = findChildVnodeByVnode(to_dir_vnode, to_file.UTF8String);
        if(to_vnode == 0) {
            printf("[-] Couldn't find file (to): %s", to);
            return -1;
        }
    }
    
    uint64_t from_vnode = getVnodeAtPath(from);
    if(from_vnode == -1) {
        NSString *from_dir = [[NSString stringWithUTF8String:from] stringByDeletingLastPathComponent];
        NSString *from_file = [[NSString stringWithUTF8String:from] lastPathComponent];
        uint64_t from_dir_vnode = getVnodeAtPathByChdir(from_dir.UTF8String);
        from_vnode = findChildVnodeByVnode(from_dir_vnode, from_file.UTF8String);
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

uint64_t funVnodeUnRedirectFile(uint64_t orig_to_vnode, uint64_t orig_nc_vp)
{
    uint64_t to_vnode_nc = kread64_kfd(orig_to_vnode + off_vnode_v_nclinks_lh_first);
    kwrite64_kfd(to_vnode_nc + off_namecache_nc_vp, orig_nc_vp);
    return 0;
}

int userspaceReboot(void) {
    kern_return_t ret = 0;
    xpc_object_t xdict = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(xdict, "cmd", 5);
    xpc_object_t xreply;
    ret = unlink("/private/var/mobile/Library/MemoryMaintenance/mmaintenanced");
    if (ret && errno != ENOENT) {
        fprintf(stderr, "could not delete mmaintenanced last reboot file\n");
        return -1;
    }
    xpc_connection_t connection = xpc_connection_create_mach_service("com.apple.mmaintenanced", NULL, 0);
    if (xpc_get_type(connection) == XPC_TYPE_ERROR) {
        char* desc = xpc_copy_description((__bridge xpc_object_t _Nonnull)(xpc_get_type(connection)));
        puts(desc);
        free(desc);
        return -1;
    }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        char* desc = xpc_copy_description(event);
        puts(desc);
        free(desc);
    });
    xpc_connection_activate(connection);
    char* desc = xpc_copy_description(connection);
    puts(desc);
    printf("connection created\n");
    xpc_object_t reply = xpc_connection_send_message_with_reply_sync(connection, xdict);
    if (reply) {
        char* desc = xpc_copy_description(reply);
        puts(desc);
        free(desc);
        xpc_connection_cancel(connection);
        return 0;
    }

    return -1;
}

void overwrite(void)
{
    uint64_t orig_nc_vp = 0;
    uint64_t orig_to_vnode = 0;
    funVnodeRedirectFile("/sbin/launchd", "/var/containers/basebin/launchd-arm64e", &orig_to_vnode, &orig_nc_vp);
}
