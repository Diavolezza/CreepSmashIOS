import Foundation

/// Diagnostics of online games for test builds (compiled with the condition NETLOG): one line per event and
/// per second of play in Documents/netlog.txt. Testers send it with "Send log" in the options; on the
/// developer's iPhone it is also taken off with devicectl. Store builds write nothing.
enum NetLog {
    #if NETLOG
    static let enabled = true
    #else
    static let enabled = false
    #endif

    /// Above this size the log starts over at the next launch.
    private static let maxBytes: UInt64 = 4_000_000

    static let url: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("netlog.txt")

    nonisolated(unsafe) private static var start = Date()
    nonisolated(unsafe) private static var handle: FileHandle? = {
        guard enabled, let url else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        if !FileManager.default.fileExists(atPath: url.path) || size > maxBytes {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        h?.write(Data("--- CreepSmash \(version), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n".utf8))
        return h
    }()

    static func log(_ text: @autoclosure () -> String) {
        guard enabled, let handle else { return }
        let line = String(format: "%@ +%.3f %@\n", ISO8601DateFormatter().string(from: Date()), Date().timeIntervalSince(start), text())
        handle.write(Data(line.utf8))
        print("NETLOG", line, terminator: "")
    }
}
