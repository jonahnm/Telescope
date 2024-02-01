//
//  pplrw.h
//  kfd
//
//  Created by Seo Hyun-gyu on 1/8/24.
//

#ifndef pplrw_h
#define pplrw_h
#include <stdint.h>
int test_kttr(void);
int test_pplrw(void);
void dma_perform(void (^block)(void));
void dma_writevirt32(uint64_t pa, uint32_t val);
void dma_writevirt64(uint64_t pa, uint64_t val);
#endif /* pplrw_h */
