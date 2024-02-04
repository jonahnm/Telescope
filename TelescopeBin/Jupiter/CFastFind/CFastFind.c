//
//  CFastFind.c
//  CFastFind
//
//  Created by Linus Henze.
//  Copyright © 2021/2022 Pinauten GmbH. All rights reserved.
//

// Some utils for the offset finder
// I mean, I could have written them in Swift
// But then I wouldn't have been able to just copy+paste from the original Fugu and Fugu14
// (Swift implementation would probably be slower as well)

#include "include/CFastFind.h"

bool CFastFind(const void* __nonnull buffer, size_t bufLen, const uint32_t* __nonnull insts, size_t instLen, size_t* __nonnull offset) {
    if (instLen == 0) {
        return false;
    }
    
    uint32_t *ptr = (uint32_t*) buffer;
    for (size_t i = 0; i < (bufLen/4 - instLen); i++) {
        bool found = true;
        for (int j = 0; j < instLen; j++) {
            if (ptr[i+j] != insts[j]) {
                found = false;
                break;
            }
        }
        
        if (found) {
            *offset = i * 4;
            return true;
        }
    }
    
    return false;
}

/**
 * Emulate an adr instruction at the given pc value
 * Returns adr destination
 */
uint64_t aarch64_emulate_adr(uint32_t instruction, uint64_t pc) {
    // Check that this is an adr instruction
    if ((instruction & 0x9F000000) != 0x10000000) {
        return 0;
    }
    
    int32_t imm = (instruction & 0xFFFFE0) >> 3;
    imm |= (instruction & 0x60000000) >> 29;
    if (instruction & 0x800000) {
        // Sign extend
        imm |= 0xFFE00000;
    }
    
    // Emulate
    return pc + imm;
}

/**
 * Emulate a b/bl instruction at the given pc value
 * Returns branch destination
 */
uint64_t aarch64_emulate_branch(uint32_t instruction, uint64_t pc) {
    // Check that this is a branch instruction
    if ((instruction & 0x7C000000) != 0x14000000) {
        return 0;
    }
    
    int32_t imm = (instruction & 0x3FFFFFF) << 2;
    if (instruction & 0x2000000) {
        // Sign extend
        imm |= 0xFC000000;
    }
    
    // Emulate
    return pc + imm;
}

uint64_t aarch64_emulate_b(uint32_t instr, uint64_t pc) {
    // Make sure this is a normal branch
    if ((instr & 0x80000000) != 0) {
        return 0;
    }
    
    // Checks that this is a b
    return aarch64_emulate_branch(instr, pc);
}

uint64_t aarch64_emulate_bl(uint32_t instr, uint64_t pc) {
    // Make sure this is not a normal branch
    if ((instr & 0x80000000) != 0x80000000) {
        return 0;
    }
    
    // Checks that this is a bl
    return aarch64_emulate_branch(instr, pc);
}

/**
 * Emulate a compare and branch instruction at the given pc value
 * Returns branch destination
 */
uint64_t aarch64_emulate_compare_branch(uint32_t instruction, uint64_t pc) {
    // Check that this is a compare and branch instruction
    if ((instruction & 0x7E000000) != 0x34000000) {
        return 0;
    }
    
    int32_t imm = (instruction & 0xFFFFE0) >> 3;
    if (instruction & 0x800000) {
        // Sign extend
        imm |= 0xFF000000;
    }
    
    // Emulate
    return pc + imm;
}

/**
 * Emulate a conditional branch at the given pc value
 * Returns branch destination
 */
uint64_t aarch64_emulate_conditional_branch(uint32_t instruction, uint64_t pc) {
    // Check that this is a conditional branch instruction
    if ((instruction & 0xFF000010) != 0x54000000) {
        return 0;
    }
    
    int32_t imm = (instruction & 0xFFFFE0) >> 3;
    if (instruction & 0x800000) {
        // Sign extend
        imm |= 0xFF000000;
    }
    
    // Emulate
    return pc + imm;
}

/**
 * Emulate an adrp instruction at the given pc value
 * Returns adrp destination
 */
uint64_t aarch64_emulate_adrp(uint32_t instruction, uint64_t pc) {
    // Check that this is an adrp instruction
    if ((instruction & 0x9F000000) != 0x90000000) {
        return 0;
    }
    
    // Calculate imm from hi and lo
    int32_t imm_hi_lo = (instruction & 0xFFFFE0) >> 3;
    imm_hi_lo |= (instruction & 0x60000000) >> 29;
    if (instruction & 0x800000) {
        // Sign extend
        imm_hi_lo |= 0xFFE00000;
    }
    
    // Build real imm
    int64_t imm = ((int64_t) imm_hi_lo << 12);
    
    // Emulate
    return (pc & ~(0xFFFULL)) + imm;
}

bool aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm) {
    // Check that this is an add instruction with immediate
    if ((instruction & 0xFF000000) != 0x91000000) {
        return 0;
    }
    
    int32_t imm12 = (instruction & 0x3FFC00) >> 10;
    
    uint8_t shift = (instruction & 0xC00000) >> 22;
    switch (shift) {
        case 0:
            *imm = imm12;
            break;
            
        case 1:
            *imm = imm12 << 12;
            break;
            
        default:
            return false;
    }
    
    *dst = instruction & 0x1F;
    *src = (instruction >> 5) & 0x1F;
    
    return true;
}

/**
 * Emulate an adrp and add instruction at the given pc value
 * Returns destination
 */
uint64_t aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc) {
    uint64_t adrp_target = aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    
    uint32_t addDst;
    uint32_t addSrc;
    uint32_t addImm;
    if (!aarch64_emulate_add_imm(addInstruction, &addDst, &addSrc, &addImm)) {
        return 0;
    }
    
    if ((instruction & 0x1F) != addSrc) {
        return 0;
    }
    
    // Emulate
    return adrp_target + (uint64_t) addImm;
}

/**
 * Emulate an adrp and ldr instruction at the given pc value
 * Returns destination
 */
uint64_t aarch64_emulate_adrp_ldr(uint32_t instruction, uint32_t ldrInstruction, uint64_t pc) {
    uint64_t adrp_target = aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    
    if ((instruction & 0x1F) != ((ldrInstruction >> 5) & 0x1F)) {
        return 0;
    }
    
    if ((ldrInstruction & 0xFFC00000) != 0xF9400000) {
        return 0;
    }
    
    uint32_t imm12 = ((ldrInstruction >> 10) & 0xFFF) << 3;
    
    // Emulate
    return adrp_target + (uint64_t) imm12;
}

uint64_t aarch64_emulate_ldr(uint32_t ldrInstruction, uint64_t pc) {
    if ((ldrInstruction & 0xFF000000) != 0x18000000) {
        if ((ldrInstruction & 0xFF000000) != 0x58000000) {
            return 0;
        }
    }
    
    uint32_t imm19 = ((ldrInstruction >> 5) & 0x7FFFF) << 2;
    
    // Emulate
    return pc + (uint64_t) imm19;
}

uint64_t aarch64_get_ldr_off(uint32_t ldrInstruction) {
    if ((ldrInstruction & 0xFFC00000) != 0xF9400000) {
        return 0;
    }
    
    uint32_t imm12 = ((ldrInstruction >> 10) & 0xFFF) << 3;
    
    return (uint64_t) imm12;
}

/**
 * Find xref to an address, data or code
 *
 * \param start Start address
 * \param end End address
 * \param xrefTo The address for which a xref should be found
 */
uint64_t find_xref_to(const void *start, const void *end, uint64_t xrefTo, uint64_t pc) {
    uint32_t *cur = (uint32_t*) start;
    
    while (cur < (uint32_t*) end) {
        uint32_t inst = *cur;
        uint64_t xref = aarch64_emulate_adr(inst, pc);
        if (!xref) {
            xref = aarch64_emulate_adrp_add(inst, *(cur+1), pc);
            if (!xref) {
                xref = aarch64_emulate_branch(inst, pc);
                if (!xref) {
                    xref = aarch64_emulate_compare_branch(inst, pc);
                    if (!xref) {
                        xref = aarch64_emulate_conditional_branch(inst, pc);
                    }
                }
            }
        }
        
        if (xref == xrefTo) {
            return pc;
        }
        
        cur++;
        pc += 4;
    }
    
    return 0;
}

/**
 * Find xref to some data
 *
 * \param start Start address
 * \param end End address
 * \param xrefTo The address for which a xref should be found
 */
uint64_t find_xref_to_data(const void *start, const void *end, uint64_t xrefTo, uint64_t pc) {
    uint32_t *cur = (uint32_t*) start;
    
    while (cur < (uint32_t*) end) {
        uint32_t inst = *cur;
        uint64_t xref = aarch64_emulate_adr(inst, pc);
        if (!xref) {
            xref = aarch64_emulate_adrp_add(inst, *(cur+1), pc);
        }
        
        if (xref == xrefTo) {
            return pc;
        }
        
        cur++;
        pc += 4;
    }
    
    return 0;
}

/**
 * Find xref to some code, checking only branches
 *
 * \param start Start address
 * \param end End address
 * \param xrefTo The address for which a xref should be found
 */
uint64_t find_xref_branch(const void *start, const void *end, uint64_t xrefTo, uint64_t pc) {
    uint32_t *cur = (uint32_t*) start;
    
    while (cur < (uint32_t*) end) {
        uint32_t inst = *cur;
        uint64_t xref = aarch64_emulate_branch(inst, pc);
        if (!xref) {
            xref = aarch64_emulate_compare_branch(inst, pc);
            if (!xref) {
                xref = aarch64_emulate_conditional_branch(inst, pc);
            }
        }
        
        if (xref == xrefTo) {
            return pc;
        }
        
        cur++;
        pc += 4;
    }
    
    return 0;
}
