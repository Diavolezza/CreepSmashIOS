import Foundation

/// Diagnostics of online games for development builds (compiled with the condition NETLOG): one line per
/// event and per second of play in Documents/netlog.txt (taken off the iPhone with devicectl). Store builds
/// write nothing.
enum NetLog {
    #if NETLOG
    static let enabled = true
    #else
    static let enabled = false
    #endif

    nonisolated(unsafe) private static var start = Date()
    nonisolated(unsafe) private static var handle: FileHandle? = {
        guard enabled, let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = dir.appendingPathComponent("netlog.txt")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    static func log(_ text: @autoclosure () -> String) {
        guard enabled, let handle else { return }
        let line = String(format: "%@ +%.3f %@\n", ISO8601DateFormatter().string(from: Date()), Date().timeIntervalSince(start), text())
        handle.write(Data(line.utf8))
        print("NETLOG", line, terminator: "")
    }
}
