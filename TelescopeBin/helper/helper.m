//
//  helper.c
//  helper
//

#include "helper.h"
#include <objc/objc.h>
#include <spawn.h>
#include <stdarg.h>
#include <sys/_types/_null.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/mman.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>


void printUsage() 
{
    NSLog(@"Usage: helper copy <source_path> <destination_path>");
}

typedef struct __SecCode const *SecStaticCodeRef;
typedef CF_OPTIONS(uint32_t, SecCSFlags) {
    kSecCSDefaultFlags = 0
};

extern SecStaticCodeRef getStaticCodeRef(NSString *binaryPath);
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes, SecStaticCodeRef *staticCode);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *information);
CFDataRef SecCertificateCopyExtensionValue(SecCertificateRef certificate, CFTypeRef extensionOID, bool *isCritical);
void SecPolicySetOptionsValue(SecPolicyRef policy, CFStringRef key, CFTypeRef value);
extern CFStringRef kSecCodeInfoEntitlementsDict;
extern CFStringRef kSecCodeInfoCertificates;
extern CFStringRef kSecPolicyAppleiPhoneApplicationSigning;
extern CFStringRef kSecPolicyAppleiPhoneProfileApplicationSigning;
extern CFStringRef kSecPolicyLeafMarkerOid;

#define kSecCSRequirementInformation 1 << 2
#define kSecCSSigningInformation 1 << 1


SecStaticCodeRef GetStaticCodeRef(NSString *binaryPath) 
{
    if(binaryPath == nil)
    {
        return NULL;
    }
    
    CFURLRef binaryURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)binaryPath, kCFURLPOSIXPathStyle, false);
    
    SecStaticCodeRef codeRef = NULL;
    OSStatus result;
    
    result = SecStaticCodeCreateWithPathAndAttributes(binaryURL, kSecCSDefaultFlags, NULL, &codeRef);
    
    CFRelease(binaryURL);
        
    return codeRef;
}

NSDictionary* DumpEntitlements(SecStaticCodeRef codeRef) 
{
    CFDictionaryRef signingInfo = NULL;
    OSStatus result;
    
    result = SecCodeCopySigningInformation(codeRef, kSecCSRequirementInformation, &signingInfo);
    
    
    NSDictionary *entitlementsNSDict = nil;
    
    CFDictionaryRef entitlements = CFDictionaryGetValue(signingInfo, kSecCodeInfoEntitlementsDict);
    if(CFGetTypeID(entitlements) != CFDictionaryGetTypeID()) 
    {
    } else 
    {
        entitlementsNSDict = (__bridge NSDictionary *)(entitlements);
        return entitlementsNSDict;
    }
    
    CFRelease(signingInfo);
    return entitlementsNSDict;
}

NSDictionary* DumpEntitlementsFromBinaryAtPath(NSString *binaryPath) 
{
    if(binaryPath == nil) { return nil; }
    SecStaticCodeRef codeRef = GetStaticCodeRef(binaryPath);
    if(codeRef == NULL) {  return nil;  }
    NSDictionary *entitlements = DumpEntitlements(codeRef);
    CFRelease(codeRef);

    return entitlements;
}

static uint64_t PF_RETURN_PAC(void* executable_map, size_t executable_length) 
{
    // mov w0, #1
    // ret
    static const unsigned char needle[] = 
    {
        0xCF, 
        0xFA, 
        0xED, 
        0xFE, 
        0x0C, 
        0x00, 
        0x00, 
        0x01, 
        0x02, 
        0x00, 
        0x00, 
        0x80
    };
    unsigned char* offset = memmem(executable_map, executable_length, needle, sizeof(needle));
    if (!offset) 
    {
        return 0;
    }

    // Patch the last four bytes to be 0
    offset[sizeof(needle) - 4] = 0x00;
    offset[sizeof(needle) - 3] = 0x00;
    offset[sizeof(needle) - 2] = 0x00;
    offset[sizeof(needle) - 1] = 0x00;

    return offset - (unsigned char*)executable_map;
}

bool PatchLoader(const char *patchee) 
{
    const char *targetPath = patchee;
    int fd = open(targetPath, O_RDWR | O_CLOEXEC); // Open in read-write mode
    if (fd == -1) 
    {
        // Handle error opening the file
        return false;
    }

    off_t targetLength = lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);
    void *targetMap = mmap(NULL, targetLength, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

    if (targetMap == MAP_FAILED) 
    {
        // Handle error mapping the file
        close(fd);
        return false;
    }
    uint64_t offset = PF_RETURN_PAC(targetMap, targetLength);
    munmap(targetMap, targetLength);
    close(fd);
    return true;
}


int main(int argc, char* argv[]) 
{
    NSString *command = @(argv[1]);
    NSString *sourcePath = @(argv[2]);

    if ([command isEqualToString:@"copy"]) 
    {
        NSString *destinationPath = @(argv[3]).stringByResolvingSymlinksInPath;
        NSError *copyError;
        [NSFileManager.defaultManager createDirectoryAtPath:destinationPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:NULL error:NULL];
        [[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:destinationPath error:&copyError];
        NSLog(@"Copy completed successfully.");
    } else if ([command isEqualToString:@"rm"]) 
    {
        if ([NSFileManager.defaultManager fileExistsAtPath:sourcePath])
        {
            NSError *rmError;
            [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:&rmError];
        }
        NSLog(@"rm completed successfully.");
    } else if ([command isEqualToString:@"mkdir"]) 
    {
        NSDictionary* attr = @{NSFilePosixPermissions:@(0755), NSFileOwnerAccountID:@(501), NSFileGroupOwnerAccountID:@(501)};
        [NSFileManager.defaultManager createDirectoryAtPath:sourcePath withIntermediateDirectories:YES attributes:attr error:NULL];
        NSLog(@"mkdir completed successfully.");
    } else if ([command isEqualToString:@"mklink"]) 
    {
        NSString *destinationPath = @(argv[3]);
        NSDictionary* attr = @{NSFilePosixPermissions:@(0755), NSFileOwnerAccountID:@(501), NSFileGroupOwnerAccountID:@(501)};
        [NSFileManager.defaultManager createDirectoryAtPath:destinationPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:attr error:NULL];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:@"/var/jb" withDestinationPath:destinationPath error:NULL];

        chmod(destinationPath.fileSystemRepresentation, 0755);
        chown(destinationPath.fileSystemRepresentation, 501, 501);

        NSLog(@"mklink completed successfully.");
    } else if ([command isEqualToString:@"own"]) 
    {
        chown(sourcePath.fileSystemRepresentation, 501, 501);
        NSLog(@"own completed successfully.");
    } else if ([command isEqualToString:@"pacstrip"]) 
    {
        PatchLoader(sourcePath.UTF8String);
        NSLog(@"Patch completed successfully.");
    } else if ([command isEqualToString:@"xmldump"]) 
    {
        NSMutableDictionary * data = DumpEntitlementsFromBinaryAtPath(sourcePath).mutableCopy;
        
        data[@"platform-application"] = @YES;

        NSString *destinationPath = @(argv[3]).stringByResolvingSymlinksInPath;
        [data writeToFile:destinationPath atomically:NO];
        NSLog(@"Dump completed successfully.");
    } else
    {
        NSLog(@"Invalid command.");
        return -1;
    }

    return 0;
}