import Foundation
import Network
import UIKit

/// Game Center round: the connection to the last opponent has dropped without a goodbye. Who is to blame?
/// The device that is online (and was all along) goes on and wins; the one that lost its network, was in the
/// background or was stopped gets no result. Without this both devices would count the other one's
/// surrender and both win.
@MainActor
final class ConnectionCheck {
    /// An outage (no network, app in the background) within this time before the check means: offline.
    static let outageWindow: TimeInterval = 60
    private nonisolated static let probeURL = URL(string: "https://www.apple.com/library/test/success.html")!

    private nonisolated let monitor = NWPathMonitor()
    private var lastOutage: Date?
    private var satisfied = true
    private var observers: [NSObjectProtocol] = []

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(ok) }
        }
        monitor.start(queue: .global(qos: .utility))
        // Away from the game is like offline: the connection may have dropped because of it.
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lastOutage = Date() }
            })
        }
    }

    deinit {
        monitor.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func pathChanged(_ ok: Bool) {
        if ok != satisfied { NetLog.log("network path \(ok ? "satisfied" : "unsatisfied")") }
        satisfied = ok
        if !ok { lastOutage = Date() }
    }

    /// Online now, and without outage in the last `outageWindow`: a request to Apple succeeds.
    func isOnline() async -> Bool {
        if let lastOutage, Date().timeIntervalSince(lastOutage) < Self.outageWindow {
            NetLog.log("connection check: outage \(Int(Date().timeIntervalSince(lastOutage))) s ago")
            return false
        }
        guard satisfied else { return false }
        for _ in 0..<2 where await Self.probe() { return true }
        return false
    }

    /// The answer is checked, not trusted: status 200, small, with the expected content.
    private nonisolated static func probe() async -> Bool {
        let request = URLRequest(url: probeURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4096 else { return false }
        return String(decoding: data, as: UTF8.self).contains("<BODY>Success</BODY>")
    }
}
