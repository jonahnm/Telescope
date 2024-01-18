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

#include "envbuf.h"
#include "fishhook.h"

#define    CS_VALID        0x0000001    /* dynamically valid */
#define CS_ADHOC        0x0000002    /* ad hoc signed */
#define CS_GET_TASK_ALLOW    0x0000004    /* has get-task-allow entitlement */
#define CS_INSTALLER        0x0000008    /* has installer entitlement */

#define    CS_HARD            0x0000100    /* don't load invalid pages */
#define    CS_KILL            0x0000200    /* kill process if it becomes invalid */
#define CS_CHECK_EXPIRATION    0x0000400    /* force expiration checking */
#define CS_RESTRICT        0x0000800    /* tell dyld to treat restricted */
#define CS_ENFORCEMENT        0x0001000    /* require enforcement */
#define CS_REQUIRE_LV        0x0002000    /* require library validation */
#define CS_ENTITLEMENTS_VALIDATED    0x0004000

#define    CS_ALLOWED_MACHO    0x00ffffe

#define CS_EXEC_SET_HARD    0x0100000    /* set CS_HARD on any exec'ed process */
#define CS_EXEC_SET_KILL    0x0200000    /* set CS_KILL on any exec'ed process */
#define CS_EXEC_SET_ENFORCEMENT    0x0400000    /* set CS_ENFORCEMENT on any exec'ed process */
#define CS_EXEC_SET_INSTALLER    0x0800000    /* set CS_INSTALLER on any exec'ed process */

#define CS_KILLED        0x1000000    /* was killed by kernel for invalidity */
#define CS_DYLD_PLATFORM    0x2000000    /* dyld used to load this is a platform binary */
#define CS_PLATFORM_BINARY    0x4000000    /* this is a platform binary */
#define CS_PLATFORM_PATH    0x8000000    /* platform binary by the fact of path (osx only) */

/* csops  operations */
#define CS_OPS_STATUS       0   /* return status */
#define CS_OPS_MARKINVALID  1   /* invalidate process */
#define CS_OPS_MARKHARD     2   /* set HARD flag */
#define CS_OPS_MARKKILL     3   /* set KILL flag (sticky) */
#define CS_OPS_PIDPATH      4   /* get executable's pathname */
#define CS_OPS_CDHASH       5   /* get code directory hash */
#define CS_OPS_PIDOFFSET    6   /* get offset of active Mach-o slice */
#define CS_OPS_ENTITLEMENTS_BLOB 7  /* get entitlements blob */
#define CS_OPS_MARKRESTRICT 8   /* set RESTRICT flag (sticky) */


int (*SpawnPOld)(pid_t * pid, const char * path, const posix_spawn_file_actions_t * ac, const posix_spawnattr_t * ab, char *const __argv[], char *const __envp[]);
int (*SpawnOld)(pid_t * pid, const char * path, const posix_spawn_file_actions_t * ac, const posix_spawnattr_t * ab, char *const __argv[], char *const __envp[]);
int (*CodeSignOptionsOld)(pid_t pid, unsigned int  ops, void * useraddr, size_t usersize);
int (*CodeSignOptionsAuditTokenOld)(pid_t pid, unsigned int  ops, void * useraddr, size_t usersize, audit_token_t * token);

extern int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr, int (*OldSpawn)());


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

char* TelescopeDir(void) 
{
    const char* hash = GenerateRandomString(13, 13).UTF8String;
    static char result[MAXPATHLEN];
    sprintf(result, "/private/preboot/%s", hash);
    return result;
}

void LogToFile(const char *format, ...)
{
    // Open the file in append mode
    FILE *file = fopen("/var/mobile/telescope.log", "a+");
    
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

BOOL IsMachOExecutable(NSString *filePath) 
{
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    
    if (fileHandle == nil) {
        NSLog(@"Error opening file at path %@", filePath);
        return NO;
    }
    
    // Read the first 4 bytes (sizeof(magic)) from the file
    NSData *magicData = [fileHandle readDataOfLength:sizeof(uint32_t)];
    
    // Close the file handle
    [fileHandle closeFile];
    
    if (magicData.length != sizeof(uint32_t)) {
        NSLog(@"Error reading magic number from file at path %@", filePath);
        return NO;
    }
    
    uint32_t magicValue;
    [magicData getBytes:&magicValue length:sizeof(uint32_t)];
    
    // Check if the magic number corresponds to a Mach-O executable
    if (magicValue == MH_MAGIC || magicValue == MH_MAGIC_64 || magicValue == MH_CIGAM || magicValue == MH_CIGAM_64) {
        return YES;
    } else {
        return NO;
    }
}

#define prin_error LogToFile("%s", err.UTF8String); LogToFile("%s", out.UTF8String);

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);
int posix_spawnattr_set_launch_type_np(posix_spawnattr_t *attr, uint8_t launch_type);

BOOL HasJBPathComponent(NSString *path) 
{
    NSArray *pathComponents = [path pathComponents];
    for (NSString *component in pathComponents) 
    {
        if ([component isEqualToString:@"jb"]) 
        {
            return YES;
        }
    }
    return NO;
}

void TriggerResign()
{
    char* ts_dir = TelescopeDir();    
    char signed_files[512]; sprintf(signed_files, "%s/%s", ts_dir, "signed_files");
    char copiedsign[512]; sprintf(copiedsign, "%s/%s", ts_dir, "sign");
    char copiedhelp[512]; sprintf(copiedhelp, "%s/%s", ts_dir, "helper");
    char dirrr[512]; sprintf(dirrr, "%s/%s", ts_dir, "jbfiles/");

    if ([NSFileManager.defaultManager fileExistsAtPath:@(dirrr)])
    {    
        NSMutableArray *processedFiles =  [NSMutableArray arrayWithContentsOfFile:@(signed_files)] ?: [NSMutableArray array] ; // Create an array to store file information
        
        int machoCount=0, libCount=0;
        NSString *resolvedPath = @(dirrr);
        NSDirectoryEnumerator<NSURL *> *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:resolvedPath isDirectory:YES] includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey] options:0 errorHandler:nil];

        for (NSURL *enumURL in directoryEnumerator) {
            @autoreleasepool {
                NSNumber *isSymlink;
                [enumURL getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil];
                if (isSymlink && ![isSymlink boolValue]) 
                {
                    FILE *fp = fopen(enumURL.fileSystemRepresentation, "rb");
                    if (fp != NULL)
                    {
                        if(IsMachOExecutable(@(enumURL.fileSystemRepresentation))) 
                        {
                            if (![processedFiles containsObject:enumURL.path])
                            {
                                // if ([enumURL.path containsString:@"ellekit"] ||
                                //     [enumURL.path containsString:@"CydiaSubstrate"] ||
                                //     [enumURL.path containsString:@"allowsb"])
                                // {
                                    
                                // } else 
                                {
                                    machoCount++;
                                    spawnRoot(@(copiedsign), @[enumURL.path], nil, nil, SpawnOld);
                                    [processedFiles addObject:enumURL.path];
                                }
                            }
                        }
                        fclose(fp);
                    }
                }
            }
        }

        [processedFiles writeToFile:@"/tmp/signed_files" atomically:NO];
        spawnRoot(@(copiedhelp), @[@"copy", @"/tmp/signed_files", @(signed_files)], nil, nil, SpawnOld);
    }
}

const char* InterceptNewPathCommon(const char* path, const posix_spawnattr_t * ab)
{
    // if (strcmp(path, "/usr/libexec/amfid") == 0)
    // {
    //     posix_spawnattr_set_launch_type_np(ab, 0);
    //     return [NSString stringWithFormat:@"%s/%@", TelescopeDir(), @"dead_amfid"].UTF8String;
    // }

    if (strcmp(path, "/usr/libexec/xpcproxy") == 0)
    {
        posix_spawnattr_set_launch_type_np(ab, 0);
        return [NSString stringWithFormat:@"%s/%@", TelescopeDir(), @"brainwashed_xpc"].UTF8String;
    }

    // TODO: some kind of directory/file watcher instead of resiging everything here.
    TriggerResign();
    return path;
}

int SpawnPNew(pid_t * pid, const char * path, const posix_spawn_file_actions_t * ac, const posix_spawnattr_t * ab, char *const __argv[], char *const __envp[])
{
    path = InterceptNewPathCommon(path, ab);
    LogToFile("%s\n", path);
    return SpawnPOld(pid, path, ac, ab, __argv, __envp);
}

int SpawnNew(pid_t * pid, const char * path, const posix_spawn_file_actions_t * ac, const posix_spawnattr_t * ab, char *const __argv[], char *const __envp[])
{
    path = InterceptNewPathCommon(path, ab);
    LogToFile("%s\n", path);
    return SpawnOld(pid, path, ac, ab, __argv, __envp);
}

int CodeSignOptionsNew(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) 
{
    int result = CodeSignOptionsOld(pid, ops, useraddr, usersize);
    
    if (!result && ops == 0) 
    { // CS_OPS_STATUS
        *((uint32_t *)useraddr) |= (0x4000000 | 0x0000001); // CS_PLATFORM_BINARY
        *((uint32_t *)useraddr) &= ~(CS_HARD | CS_KILL | 0x0002000 | CS_RESTRICT);
    }
    return result;
}

int CodeSignOptionsAuditTokenNew(pid_t pid, unsigned int ops, void * useraddr, size_t usersize, audit_token_t * token) 
{
    int result = CodeSignOptionsAuditTokenOld(pid, ops, useraddr, usersize, token);
    if (ops == 0) 
    { // CS_OPS_STATUS
        *((uint32_t *)useraddr) |= (0x4000000 | 0x0000001); // CS_PLATFORM_BINARY
        *((uint32_t *)useraddr) &= ~(CS_HARD | CS_KILL | 0x0002000 | CS_RESTRICT);
    }
    return result;
}

static void __attribute__((constructor)) Infect(void)
{
    LogToFile("Telescope loaded\n");
    struct rebinding rebindings[] = (struct rebinding[]){
        {"csops", CodeSignOptionsNew, (void *)&CodeSignOptionsOld},
        {"csops_audittoken", CodeSignOptionsAuditTokenNew, (void *)&CodeSignOptionsAuditTokenOld},
        {"posix_spawn", SpawnNew, (void *)&SpawnOld},
        {"posix_spawnp", SpawnPNew, (void *)&SpawnPOld}
    };
    rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
}
