#include <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <Security/Security.h>
#include <complex.h>
#include <dlfcn.h>
#include <math.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/_types/_null.h>
#include <sys/param.h>
#include <time.h>
#include <unistd.h>
#include <mach-o/loader.h>
#include <mach-o/fixup-chains.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <mach-o/fat.h>
#include <mach-o/ldsyms.h>
#include <mach-o/dyld_images.h>
#include <dirent.h>
#include <sys/stat.h>
#include <libgen.h>

#include <CommonCrypto/CommonDigest.h>

#include "fishhook.h"
#include "cs_blobs.h"

int (*OldMISValidateSignatureAndCopyInfo)(NSString* file, NSDictionary* options, NSMutableDictionary** info);
int (*BrokenMISValidateSignatureAndCopyInfo)(NSString* file, NSDictionary* options, NSMutableDictionary** info);

uint8_t *GetCodeDirectory(const char* name, uint64_t file_off) {
    FILE* fd = fopen(name, "r");

    if (fd == NULL) {
        NSLog(@"Couldn't open file");
        return NULL;
    }

    fseek(fd, 0L, SEEK_END);
    uint64_t file_len = ftell(fd);
    fseek(fd, 0L, SEEK_SET);

    if (file_off > file_len){
        NSLog(@"Error: File offset greater than length.");
        return NULL;
    }

    uint64_t off = file_off;
    fseek(fd, off, SEEK_SET);

    struct mach_header_64 mh;
    fread(&mh, sizeof(struct mach_header_64), 1, fd);

    if (mh.magic != MH_MAGIC_64){
        NSLog(@"Error: Invalid magic");
        return NULL;
    }

    off += sizeof(struct mach_header_64);
    if (off > file_len){
        NSLog(@"Error: Unexpected end of file");
        return NULL;
    }
    for (int i = 0; i < mh.ncmds; i++) {
        if (off + sizeof(struct load_command) > file_len){
            NSLog(@"Error: Unexpected end of file");
            return NULL;
        }

        const struct load_command cmd;
        fseek(fd, off, SEEK_SET);
        fread((void*)&cmd, sizeof(struct load_command), 1, fd);
        if (cmd.cmd == 0x1d) {
            uint32_t off_cs;
            fread(&off_cs, sizeof(uint32_t), 1, fd);
            uint32_t size_cs;
            fread(&size_cs, sizeof(uint32_t), 1, fd);

            if (off_cs+file_off+size_cs > file_len){
                NSLog(@"Error: Unexpected end of file");
                return NULL;
            }

            uint8_t *cd = malloc(size_cs);
            fseek(fd, off_cs+file_off, SEEK_SET);
            fread(cd, size_cs, 1, fd);
            return cd;
        } else {
            off += cmd.cmdsize;
            if (off > file_len){
                NSLog(@"Error: Unexpected end of file");
                return NULL;
            }
        }
    }
    NSLog(@"Didnt find the code signature");
    return NULL;
}

static unsigned int HashRank(const CodeDirectory *cd)
{
    uint32_t type = cd->hashType;
    unsigned int n;
    
    for (n = 0; n < sizeof(hashPriorities) / sizeof(hashPriorities[0]); ++n)
        if (hashPriorities[n] == type)
            return n + 1;
    return 0;    /* not supported */
}

int GetHash(const CodeDirectory* directory, uint8_t dst[CS_CDHASH_LEN]) {
    uint32_t realsize = ntohl(directory->length);
    
    if (ntohl(directory->magic) != CSMAGIC_CODEDIRECTORY) {
        NSLog(@"[get_hash] wtf, not CSMAGIC_CODEDIRECTORY?!");
        return 1;
    }
    
    uint8_t out[CS_HASH_MAX_SIZE];
    uint8_t hash_type = directory->hashType;

    switch (hash_type) {
        case CS_HASHTYPE_SHA1:
            CC_SHA1(directory, realsize, out);
            break;

        case CS_HASHTYPE_SHA256:
        case CS_HASHTYPE_SHA256_TRUNCATED:
            CC_SHA256(directory, realsize, out);
            break;

        case CS_HASHTYPE_SHA384:
            CC_SHA384(directory, realsize, out);
            break;

        default:
            NSLog(@"[get_hash] Unknown hash type: 0x%x", hash_type);
            return 2;
    }

    memcpy(dst, out, CS_CDHASH_LEN);
    return 0;
}

int ParseSuperblob(uint8_t *code_dir, uint8_t dst[CS_CDHASH_LEN]) {
    int ret = 1;
    const CS_SuperBlob *sb = (const CS_SuperBlob *)code_dir;
    uint8_t highest_cd_hash_rank = 0;
    
    for (int n = 0; n < ntohl(sb->count); n++){
        const CS_BlobIndex *blobIndex = &sb->index[n];
        uint32_t type = ntohl(blobIndex->type);
        uint32_t offset = ntohl(blobIndex->offset);
        if (ntohl(sb->length) < offset) {
            NSLog(@"offset of blob #%d overflows superblob length", n);
            return 1;
        }
        
        const CodeDirectory *subBlob = (const CodeDirectory *)(code_dir + offset);
        // size_t subLength = ntohl(subBlob->length);
        
        if (type == CSSLOT_CODEDIRECTORY || (type >= CSSLOT_ALTERNATE_CODEDIRECTORIES && type < CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT)) {
            uint8_t rank = HashRank(subBlob);
            
            if (rank > highest_cd_hash_rank) {
                ret = GetHash(subBlob, dst);
                highest_cd_hash_rank = rank;
            }
        }
    }

    return ret;
}

void LogToFile(const char *format, ...)
{
    // Open the file in append mode
    FILE *file = fopen("/var/mobile/telescope_amfid.log", "a+");
    
    if (file == NULL) {
        // Failed to open the file
        perror("Error opening file");
        return;
    }

    // Initialize variable arguments
    va_list args;
    va_start(args, format);

    // Use vfprintf to write to the file
    vfprintf(file, format, args);

    // Clean up variable arguments
    va_end(args);

    // Close the file
    fclose(file);
}


int NewMISValidateSignatureAndCopyInfo(NSString* file, NSDictionary* options, NSMutableDictionary** info) 
{
    LogToFile("We got called! %@ with %@ (info: %@)\n", file, options, *info);

    int origret = OldMISValidateSignatureAndCopyInfo(file, options, info);
    LogToFile("We got called! AFTER ACTUAL %@ with %@ (info: %@)\n", file, options, *info);

    if (![*info objectForKey:@"CdHash"]) {
        NSNumber* file_offset = [options objectForKey:@"UniversalFileOffset"];
        uint64_t file_off = [file_offset unsignedLongLongValue];

        uint8_t* code_directory = GetCodeDirectory([file UTF8String], file_off);
        if (!code_directory) {
            LogToFile("Can't get code_directory\n");
            return origret;
        }

        uint8_t cd_hash[CS_CDHASH_LEN];

        if (ParseSuperblob(code_directory, cd_hash)) {
            LogToFile("Ours failed\n");
            return origret;
        }

        *info = [[NSMutableDictionary alloc] init];
        [*info setValue:[[NSData alloc] initWithBytes:cd_hash length:sizeof(cd_hash)] forKey:@"CdHash"];
        LogToFile("ours: %@\n", *info);
    }
    return 0;
}

static void __attribute__((constructor)) Infect(void)
{
    void *libmis = dlopen("/usr/lib/libmis.dylib", RTLD_NOW); //Force binding now
    OldMISValidateSignatureAndCopyInfo = dlsym(libmis, "MISValidateSignatureAndCopyInfo");
    struct rebinding rebindings[] = (struct rebinding[]){
        {"MISValidateSignatureAndCopyInfo", NewMISValidateSignatureAndCopyInfo, (void *)&BrokenMISValidateSignatureAndCopyInfo}
    };
    rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
}
