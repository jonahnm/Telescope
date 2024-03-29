#import <Foundation/Foundation.h>

#import "trustcache_structs.h"
// Thanks KpwnZ
// 742 cdhashes fit into one page
#define TC_ENTRY_COUNT_PER_PAGE 742

@class JupiterTCPage;

extern NSMutableArray<JupiterTCPage *> *gTCPages;
extern NSMutableArray<NSNumber *> *gTCUnusedAllocations;
BOOL tcPagesRecover(void);
void tcPagesChanged(void);


@interface JupiterTCPage : NSObject
{
	trustcache_page* _page;
}

@property (nonatomic) uint64_t kaddr;

- (void)updateTCPage;

- (instancetype)initWithKernelAddress:(uint64_t)kaddr;
- (instancetype)initAllocateAndLink;

- (void)sort;
- (uint32_t)amountOfSlotsLeft;
- (BOOL)addEntry:(trustcache_entry)entry;
- (BOOL)addEntry2:(trustcache_entry2)entry;
- (BOOL)removeEntry:(trustcache_entry)entry;
- (BOOL)removeEntry2:(trustcache_entry2)entry;

- (void)unlinkAndFree;

@end