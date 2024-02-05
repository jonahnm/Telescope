//
//  kallocation.swift
//  Telescope
//
//  Created by Jonah Butler on 2/5/24.
//

import Foundation
@objc class kallocation: NSObject {
    private static var kallocPipes: [(UInt64,(Int32,Int32))] = []
    @objc public static func kalloc(size: Int) -> UInt64 {
        var newPipe: [Int32] = [0,0]
        guard pipe(&newPipe) != -1 else {
            NSLog("Pipe failed.")
            return 0
        }
        var buf = [UInt8](repeating: 0, count: size)
        write(newPipe[1], &buf, size)
        let proc_fd_ofiles = kread64_ptr_kfd(get_current_proc() + 0xf8)
        let fproc = kread64_ptr_kfd(proc_fd_ofiles + UInt64(newPipe[0] * 8))
        let fglob = kread64_ptr_kfd(fproc + 0x10)
        let rawpipe = kread64_ptr_kfd(fglob + 0x38)
        let pipebufoff = UInt64(MemoryLayout<u_int>.size * 3)
        let pipeBuf = kread64_ptr_kfd(rawpipe + pipebufoff)
        kallocPipes.append((pipeBuf,(newPipe[0],newPipe[1])))
        return pipeBuf
    }
    @objc public static func addPipe(allocLoc: UInt64,pipe0: Int32,pipe1: Int32) {
        kallocPipes.append((allocLoc,(pipe0,pipe1)))
    }
    @objc public static func kfree(whereis: UInt64) {
        for i in 1..<kallocPipes.count {
            let currentPipe = kallocPipes[i]
            if currentPipe.0 == whereis {
                close(currentPipe.1.0)
                close(currentPipe.1.1)
                kallocPipes.remove(at: i)
                break
            }
        }
    }
}
