//
//  fugufinder.swift
//  kfd-meow
//
//  Created by mizole on 2024/01/05.
//

import Foundation
import KernelPatchfinder

public func prepare_kpf() -> Bool {
    guard KernelPatchfinder.running != nil else {
        let status = grabkernel(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path + "/kernel.img4")
        if(status == 0) {
            exit(-1)
        } else {
            return false
        }
    }
    return true
}

@objc class objcbridge: NSObject {
    
    @objc public func find_base() -> UInt64 {
        return KernelPatchfinder.running?.baseAddress ?? 0x0
    }
    @objc public func find_ptov_table() -> UInt64 {
        return KernelPatchfinder.running?.ptov_data?.table ?? 0x0
    }
    @objc public func find_gPhysBase() -> UInt64 {
        return KernelPatchfinder.running?.ptov_data?.physBase ?? 0x0
    }
    @objc public func find_gPhysSize() -> UInt64 {
        return UInt64(KernelPatchfinder.running?.ptov_data?.physBase ?? 0x0) + 0x8
    }
    @objc public func find_gVirtBase() -> UInt64 {
        return KernelPatchfinder.running?.ptov_data?.virtBase ?? 0x0
    }
    @objc public func find_vn_kqfilter () -> UInt64 {
        return KernelPatchfinder.running?.vn_kqfilter ?? 0x0
    }
    @objc public func find_perfmon_devices() -> UInt64 {
        return KernelPatchfinder.running?.perfmon_devices ?? 0x0
    }
    @objc public func find_perfmon_dev_open() -> UInt64 {
        return KernelPatchfinder.running?.perfmon_dev_open ?? 0x0
    }
    @objc public func find_cdevsw() -> UInt64 {
        return KernelPatchfinder.running?.cdevsw ?? 0x0
    }
    @objc public func find_vm_pages() -> UInt64 {
        return KernelPatchfinder.running?.vm_pages ?? 0x0
    }
    @objc public func find_vm_page_array_beginning() -> UInt64 {
        return KernelPatchfinder.running?.vm_page_array.beginning ?? 0x0
    }
    @objc public func find_vm_page_array_ending() -> UInt64 {
        return KernelPatchfinder.running?.vm_page_array.ending ?? 0x0
    }
    @objc public func find_vm_first_phys_ppnum() -> UInt64 {
        return UInt64(KernelPatchfinder.running?.vm_page_array.ending ?? 0x0) + 0x8
    }
    @objc public func find_ITK_SPACE() -> UInt64 {
        return KernelPatchfinder.running?.ITK_SPACE ?? 0x0
    }
    @objc public func find_ktrr() -> UInt64 {
        return KernelPatchfinder.running?.ktrr ?? 0x0
    }
}
