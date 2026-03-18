import Foundation
import os

let appLogger = Logger(subsystem: "com.vgearen.StockMonitor", category: "lifecycle")

/// 写文件日志到 ~/Library/Logs/StockMonitor/app.log
func logToFile(_ message: String) {
    let fm = FileManager.default
    guard let logDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Logs/StockMonitor") else { return }
    try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logFile = logDir.appendingPathComponent("app.log")

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
