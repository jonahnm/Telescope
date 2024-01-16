//
//  TextLog.swift
//  Telescope
//
//  Created by Jonah Butler on 1/16/24.
//

import Foundation
public struct TextLog: TextOutputStream {

    /// Appends the given string to the stream.
    public mutating func write(_ string: String) {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .allDomainsMask)
        let documentDirectoryPath = paths.first!
        let log = documentDirectoryPath.appendingPathComponent("telescopelog.txt")

        do {
            let handle = try FileHandle(forWritingTo: log)
            handle.seekToEndOfFile()
            handle.write(string.data(using: .utf8)!)
            handle.closeFile()
        } catch {
            print(error.localizedDescription)
            do {
                try string.data(using: .utf8)?.write(to: log)
            } catch {
                print(error.localizedDescription)
            }
        }

    }

}
