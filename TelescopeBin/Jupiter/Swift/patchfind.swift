import Foundation
@objc class patchfinder : NSObject {
    @objc public static func find_server() -> UInt64 {
        guard let machO = try? MachO(fromFile: "/sbin/launchd") else {
            return 0
        }
        guard let textExec = machO.pfSection(segment: "__TEXT", section: "__text") else {
            return 1
        }
        guard let stringSect = machO.pfSection(segment: "__TEXT", section: "__cstring") else {
            return 2
        }
        guard let pathStr = stringSect.addrOf("legacy-load") else {
            return 3
        }
        guard let ref = textExec.findNextXref(to: pathStr) else {
            return 4
        }
        var pc: UInt64 = ref;
        while true {
            pc = pc - 4
            if AArch64Instr.isPacibsp(textExec.instruction(at: pc) ?? 0,alsoAllowNop: false) {
                return pc
            }
        }
    }
}