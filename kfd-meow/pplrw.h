//
//  pplrw.h
//  kfd-meow
//
//  Created by mizole on 2024/01/08.
//

#ifndef pplrw_h
#define pplrw_h
int test_pplrw(void);
int test_ktrr(void);
void dma_perform(void (^block)(void));
void dma_writevirt64(uint64_t, uint64_t);
void dma_writevirt32(uint64_t pa, uint32_t val);
#endif /* pplrw_h */
