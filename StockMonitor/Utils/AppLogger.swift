import Foundation
import os

let appLogger = Logger(subsystem: "com.vgearen.Stockbar", category: "lifecycle")

/// 写文件日志到 ~/Library/Logs/StockMonitor/app.log
func logToFile(_ message: String) {
    let fm = FileManager.default
    guard let logDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Logs/Stockbar") else { return }
    try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent("app.log")

    // Log rotation: if file exceeds 1MB, keep only last 500KB
    let maxSize: UInt64 = 1_000_000
    let keepSize: Int   = 500_000
    if let attrs = try? fm.attributesOfItem(atPath: logFile.path),
       let fileSize = attrs[.size] as? UInt64,
       fileSize > maxSize,
       let data = try? Data(contentsOf: logFile),
       data.count > keepSize {
        let tail = data.suffix(keepSize)
        // Find first newline in tail to avoid partial line
        if let newlineIndex = tail.firstIndex(of: UInt8(ascii: "\n")) {
            let clean = tail.suffix(from: tail.index(after: newlineIndex))
            try? clean.write(to: logFile)
        } else {
            try? tail.write(to: logFile)
        }
    }

    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    if fm.fileExists(atPath: logFile.path),
       let handle = try? FileHandle(forWritingTo: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)!.write(to: logFile)
    }
}
