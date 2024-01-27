//
//  extractionbridge.swift
//  Telescope
//
//  Created by Jonah Butler on 1/26/24.
//

import Foundation
import Tarscape
import DataCompression
@objc class ExtractionBridge : NSObject {
    @objc public static func untar(fromURL: URL,targetURL: URL,isgz: ObjCBool) -> ObjCBool {
        do {
            if(!isgz.boolValue) {
                try FileManager.default.extractTar(at: fromURL, to: targetURL, restoreAttributes: true)
            } else {
                let gzed = try Data(contentsOf: fromURL)
                let extracteddata: Data? = gzed.gunzip()
                let temppath = NSTemporaryDirectory() + "/temp.tar"
                let tempURL = URL(filePath: temppath)
                try extracteddata?.write(to: tempURL)
                try FileManager.default.extractTar(at: tempURL, to: targetURL, restoreAttributes: true)
                try FileManager.default.removeItem(at: tempURL)
            }
            return true
        } catch {
            return false
        }
    }
}
