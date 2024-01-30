#include "pplrw.h"
#include "trustcache_structs.h"
#include <Foundation/Foundation.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#import <uuid/uuid.h>
#import "boot_info.h"
#import "JupiterTCPage.h"
#import "kallocation.h"
#import "trustcache.h"
// Thanks KpwnZ! Couldn't have done this part without your help.
#define ALLOCATED_DYNAMIC_TRUSTCACHE_SIZE 0x2000
NSMutableArray<NSNumber*> *gTCUnusedAllocations = nil;
NSMutableArray<JupiterTCPage *> *gTCPages = nil;
BOOL tcPagesRecover(void) {
    NSArray *existingTCAllocations = bootInfo_getArray(@"trustcache_allocations");
    for(NSNumber *allocNum in existingTCAllocations) {
        @autoreleasepool {
            uint64_t kaddr = [allocNum unsignedLongLongValue];
            JupiterTCPage *jptc = [[JupiterTCPage alloc] initWithKernelAddress:kaddr];
            [gTCPages addObject:jptc];
        }
    }
    NSArray *existingUnusedTCAllocations = bootInfo_getArray(@"trustcache_unused_allocations");
    if(existingTCAllocations) {
        gTCUnusedAllocations = [existingUnusedTCAllocations mutableCopy];
    }
    return (BOOL)existingTCAllocations;
 }
 void tcPagesChanged(void) {
    NSMutableArray *tcAllocations = [NSMutableArray new];
    for(JupiterTCPage *page in gTCPages) {
        @autoreleasepool {
            [tcAllocations addObject:@(page.kaddr)];
        }
    }
    bootInfo_setObject(@"trustcache_allocations",tcAllocations);
    bootInfo_setObject(@"trustcache_unused_allocations", gTCUnusedAllocations);
 }
 @implementation JupiterTCPage
 - (void)updateTCPage {
    //TODO: add some logging
    kwritebuf(self.kaddr, _page, ALLOCATED_DYNAMIC_TRUSTCACHE_SIZE);
 }
 - (instancetype)initWithKernelAddress:(uint64_t)kaddr {
   self = [super init];
    if(self) {
        _page = NULL;
        self.kaddr = kaddr;
    }
    return self;
 }
 - (instancetype)initAllocateAndLink {
 self = [super init];
 if(self) {
    _page = NULL;
    self.kaddr = 0;
    if(![self allocateInKernel])
        return nil;
    [self linkInKernel];
 }
 return self;
 }
 - (void)setKaddr:(uint64_t)kaddr {
    _kaddr = kaddr;
    NSLog(@"Kaddr being set: %p",kaddr);
    if(kaddr) {
        //TODO: add some logging
        if(_page == NULL) {
            _page = (trustcache_page *)malloc(ALLOCATED_DYNAMIC_TRUSTCACHE_SIZE);
        }
        NSLog(@"Page being written to: %p",_page);
        usleep(500);
        kreadbuf(kaddr, _page, ALLOCATED_DYNAMIC_TRUSTCACHE_SIZE);
    } else {
        _page = 0;
    }
 }
- (BOOL)allocateInKernel {
    uint64_t kaddr = 0;
    if(gTCUnusedAllocations.count) {
        kaddr = [gTCUnusedAllocations.firstObject unsignedLongLongValue];
        [gTCUnusedAllocations removeObjectAtIndex:0];
    } else {
        kaddr = (uint64_t)kalloc_msg(ALLOCATED_DYNAMIC_TRUSTCACHE_SIZE*2);
    }
    if(kaddr == 0)
        return NO;
    // TODO: add some logging
    usleep(500);
    self.kaddr = kaddr;
    trustcache_module *module = (trustcache_module *)_page;
    module->nextptr = 0;
    module->prevptr = 0;
    module->fileptr = (trustcache_file2*)(kaddr + 0x28);
    module->module_size = 0;
    uuid_generate(_page->file.uuid);
    _page->file.length = 0;
    [gTCPages addObject:self];
    tcPagesChanged();
    return YES;
}

- (void)linkInKernel {
    [self updateTCPage];
    trustCacheListAdd(self.kaddr);
}
- (void)unlinkInKernel {
    [self updateTCPage];
    trustCacheListRemove(self.kaddr);
}
- (void)freeInKernel {
    if(self.kaddr == 0)
        return;
    [gTCUnusedAllocations addObject:@(self.kaddr)];
    self.kaddr = 0;
    [gTCPages removeObject:self];
    tcPagesChanged();
}
- (void)unlinkAndFree {
    [self unlinkInKernel];
    [self freeInKernel];
}
- (void)sort {
trustcache_module *module = (trustcache_module *)_page;
qsort(module->file.entries, module->file.length, sizeof(trustcache_entry2), tcentryComparator);
}
- (uint32_t)amountOfSlotsLeft {
trustcache_module *module = (trustcache_module *)_page;
return TC_ENTRY_COUNT_PER_PAGE - module->file.length;
}
- (BOOL)addEntry:(trustcache_entry)entry {
uint32_t index = _page->file.length;
if(index >= TC_ENTRY_COUNT_PER_PAGE) {
    return NO;
}
_page->file.entries[index] = entry;
_page->file.length++;
return YES;
}
- (BOOL)addEntry2:(trustcache_entry2)entry {
trustcache_module *module = (trustcache_module *)_page;
uint32_t index = ((trustcache_module *)(module))->file.length;
if(index >= TC_ENTRY_COUNT_PER_PAGE) {
    return NO;
}
module->file.entries[index] = entry;
module->file.length++;
return YES;
}
- (int64_t)_indexOfEntry:(trustcache_entry)entry {
    trustcache_entry *entries = _page->file.entries;
    int32_t count = _page->file.length;
    int32_t left = 0;
    int32_t right = count - 1;
    while(left <= right) {
        int32_t mid = (left + right) / 2;
        int32_t cmp = memcmp(entry.hash,entries[mid].hash,CS_CDHASH_LEN);
        if(cmp == 0) {
            return mid;
        }
        if(cmp < 0) {
            right = mid - 1;
        } else {
            left = mid + 1;
        }
    }
    return -1;
}
- (int64_t)_indexOfEntry2:(trustcache_entry2)entry {
    trustcache_module *module = (trustcache_module *)_page;
    trustcache_entry2 *entries = module->file.entries;
    int32_t count = module->file.length;
    int32_t left = 0;
    int32_t right = count - 1;

    while (left <= right) {
        int32_t mid = (left + right) / 2;
        int32_t cmp = memcmp(entry.hash, entries[mid].hash, CS_CDHASH_LEN);
        if (cmp == 0) {
            return mid;
        }
        if (cmp < 0) {
            right = mid - 1;
        } else {
            left = mid + 1;
        }
    }
    return -1;
}
- (BOOL)removeEntry:(trustcache_entry)entry {
int64_t entryIndexOrNot = [self _indexOfEntry:entry];
if(entryIndexOrNot == -1)
    return NO;
uint32_t entryIndex = (uint32_t)entryIndexOrNot;
memset(_page->file.entries[entryIndex].hash,0xFF,CS_CDHASH_LEN);
[self sort];
_page->file.length--;
return YES;
}
- (BOOL)removeEntry2:(trustcache_entry2)entry {
 int64_t entryIndexOrNot = [self _indexOfEntry2:entry];
 if(entryIndexOrNot == -1)
    return NO;
uint32_t entryIndex = (uint32_t)entryIndexOrNot;
memset(((trustcache_module *)_page)->file.entries[entryIndex].hash,0xFF,CS_CDHASH_LEN);
[self sort];
((trustcache_module *)_page)->file.length--;
return YES;
}

@end