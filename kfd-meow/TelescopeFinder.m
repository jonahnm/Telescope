//
//  TelescopeFinder.m
//  Telescope
//
//  Created by knives on 1/15/24.
//


#include <CoreFoundation/CoreFoundation.h>

#include "libkfd/common.h"
#include "libkfd.h"
#include "meowfinder.h"


static unsigned char * BoyermooreHorspoolMemMem(const unsigned char* haystack, size_t hlen, const unsigned char* needle,   size_t nlen)
{
    size_t last, scan = 0;
    size_t bad_char_skip[UCHAR_MAX + 1]; /* Officially called:
                                          * bad character shift */

    /* Sanity checks on the parameters */
    if (nlen <= 0 || !haystack || !needle)
        return NULL;

    /* ---- Preprocess ---- */
    /* Initialize the table to default value */
    /* When a character is encountered that does not occur
     * in the needle, we can safely skip ahead for the whole
     * length of the needle.
     */
    for (scan = 0; scan <= UCHAR_MAX; scan = scan + 1)
        bad_char_skip[scan] = nlen;

    /* C arrays have the first byte at [0], therefore:
     * [nlen - 1] is the last byte of the array. */
    last = nlen - 1;

    /* Then populate it with the analysis of the needle */
    for (scan = 0; scan < last; scan = scan + 1)
        bad_char_skip[needle[scan]] = last - scan;

    /* ---- Do the matching ---- */

    /* Search the haystack, while the needle can still be within it. */
    while (hlen >= nlen)
    {
        /* scan from the end of the needle */
        for (scan = last; haystack[scan] == needle[scan]; scan = scan - 1)
            if (scan == 0) /* If the first byte matches, we've found it. */
                return (void *)haystack;

        /* otherwise, we need to skip some bytes and start again.
           Note that here we are getting the skip value based on the last byte
           of needle, no matter where we didn't match. So if needle is: "abcd"
           then we are skipping based on 'd' and that value will be 4, and
           for "abcdd" we again skip on 'd' but the value will be only 1.
           The alternative of pretending that the mismatched character was
           the last character is slower in the normal case (E.g. finding
           "abcd" in "...azcd..." gives 4 by using 'd' but only
           4-2==2 using 'z'. */
        hlen     -= bad_char_skip[haystack[last]];
        haystack += bad_char_skip[haystack[last]];
    }

    return NULL;
}

void GetKernelSection(uint64_t kernel_base, const char *segment, const char *section, uint64_t *addr_out, uint64_t *size_out)
{
    struct mach_header_64 kernel_header;
    kreadbuf_kfd(kernel_base, &kernel_header, sizeof(kernel_header));
    
    uint64_t cmdStart = kernel_base + sizeof(kernel_header);
    uint64_t cmdEnd = cmdStart + kernel_header.sizeofcmds;
    
    uint64_t cmdAddr = cmdStart;
    for(int ci = 0; ci < kernel_header.ncmds && cmdAddr <= cmdEnd; ci++)
    {
        struct segment_command_64 cmd;
        kreadbuf_kfd(cmdAddr, &cmd, sizeof(cmd));
        
        if(cmd.cmd == LC_SEGMENT_64)
        {
            uint64_t sectStart = cmdAddr + sizeof(cmd);
            bool finished = false;
            for(int si = 0; si < cmd.nsects; si++)
            {
                uint64_t sectAddr = sectStart + si * sizeof(struct section_64);
                struct section_64 sect;
                kreadbuf_kfd(sectAddr, &sect, sizeof(sect));
                
                if (!strcmp(cmd.segname, segment) && !strcmp(sect.sectname, section)) {
                    *addr_out = sect.addr;
                    *size_out = sect.size;
                    finished = true;
                    break;
                }
            }
            if (finished) break;
        }
        
        cmdAddr += cmd.cmdsize;
    }
}

uint64_t GetTrustCacheAddress(struct kfd* kfd)
{
    
    uint64_t textexec_text_addr = 0, textexec_text_size = 0;
    GetKernelSection(kernel_base, "__TEXT_EXEC", "__text", &textexec_text_addr, &textexec_text_size);
    
    // find "image4 interface not available"

    const char *str_target = "image4 interface not available";
    int current_offset = 0;
    uint64_t str_addr = 0;
    uint64_t searching_addr = 0x30000 + kfd->info.kernel.kernel_slide + 0xFFFFFFF007004000;
    while (current_offset < 0x1000000) {
        uint8_t *buffer = malloc(0x1000);
        kreadbuf_kfd(searching_addr + current_offset, buffer, 0x1000);
        uint8_t *str;
        str = BoyermooreHorspoolMemMem(buffer, 0x1000, str_target, strlen(str_target));
        if (str) {
            printf("[KPF_DEBUG] 0x%llx", str - buffer + searching_addr + current_offset - kfd->info.kernel.kernel_slide);
            str_addr = str - buffer + searching_addr + current_offset;
            break;
        }
        current_offset += 0x1000;
        free(buffer);
    }
    if (str_addr == 0) {
        return 0;
    }

#define ASM_ADRP(off, reg) ((0x90000000 | ((uint32_t)(((off >> 12) & 0x3) << 29)) | ((uint32_t)(((off >> 12) & (~0x3)) << 3)) | reg) & 0xF0FFFFFF)
#define ASM_ADD(imm, regdst, regsrc) (0x91000000 | (imm << 10) | (regsrc << 5) | (regdst))
#define DISASM_ADRP(__code, __off, __reg) \
    do {\
        uint64_t __offset = (int)((((__code & 0x60000000) >> 29) | ((__code & 0xFFFFE0) >> 3)) << 12); \
        *__off = __offset; \
        *__reg = (__code & 0x1f); \
    } while(0)
#define DISASM_ADD(__code, __imm, __reg1, __reg2) \
    do { \
        *__imm = ((__code & 0x003FFC00)) >> 7; \
        *__reg1 = (__code & 0x1F); \
        *__reg2 = ((__code & 0x3E0) >> 5); \
    } while(0)
    current_offset = 0;
    uint64_t trust_cache_runtime_init = 0;
    while (current_offset < textexec_text_size) {
        uint8_t *buffer = malloc(0x1000);
        kreadbuf_kfd(textexec_text_addr + current_offset, buffer, 0x1000);
        for (int i = 0; i < 0x1000; i += 4) {
            uint64_t current_addr = textexec_text_addr + current_offset + i;
            uint64_t page = current_addr & (~(uint64_t)0xFFF);
            uint64_t page_offset = (str_addr & (~(uint64_t)0xFFF)) - page;
            uint32_t code = ASM_ADRP(page_offset, 0);
            if (*(uint32_t *)(buffer + i) == code) {
                uint64_t code2 = ASM_ADD((str_addr & 0xFFF), 0, 0);
                if (*(uint32_t *)(buffer + i + 4) == code2) {
                    trust_cache_runtime_init = i + textexec_text_addr + current_offset;
                    break;
                }
            }
        }
        free(buffer);
        if (trust_cache_runtime_init) break;
        current_offset += 0x1000;
    }
    if (!trust_cache_runtime_init) {
        printf("[-] failed to find trustcache_runtime_init");
        return 0;
    }
    uint64_t code = 0;
    kreadbuf_kfd(trust_cache_runtime_init-0x64, &code, 8);
    uint32_t adrp_code = code & 0xFFFFFFFF;
    uint32_t ldr_code = (code >> 32) & 0xFFFFFFFF;
    uint64_t page_addr = 0, page_offset = 0, reg = 0;
    DISASM_ADRP(adrp_code, &page_addr, &reg);
    printf("[KPF_DEBUG] page=0x%llx reg=0x%llx", page_addr, reg);
    DISASM_ADD(ldr_code, &page_offset, &reg, &reg);
    printf("[KPF_DEBUG] pageoff=0x%llx reg=0x%llx reg=0x%llx", page_offset, reg, reg);
    uint64_t addr = (((trust_cache_runtime_init-0x64) & 0xfffffffffffff000) + page_offset + page_addr);
    uint64_t data = 0;
    kreadbuf_kfd(addr, &data, 8);
    printf("[KPF_DEBUG] data=0x%llx", data);
    
    return data + 0x20;
}
