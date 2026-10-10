import Foundation
import Network
import CreepSmashCore

/// TCP connection to the other player. Each message is sent prefixed with a 4-byte length (big endian).
/// All callbacks arrive on the main thread.
final class StreamTransport: Transport {
    private let connection: NWConnection
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?
    /// Connection is established (only used during setup).
    var onReady: (() -> Void)?
    private var closed = false

    init(connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onReady?()
                self?.onReady = nil
            case .failed, .cancelled:
                self?.lost()
            default:
                break
            }
        }
        connection.start(queue: .main)
        receiveHeader()
    }

    func send(_ data: Data) {
        guard !closed else { return }
        var packet = Data(capacity: data.count + 4)
        let length = UInt32(data.count)
        packet.append(contentsOf: [UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
        packet.append(data)
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.lost() }
        })
    }

    func close() {
        guard !closed else { return }
        closed = true
        onReceive = nil
        onClose = nil
        onReady = nil
        connection.cancel()
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, data.count == 4 {
                let length = data.reduce(0) { $0 << 8 | Int($1) }
                self.receiveBody(length)
            } else if isComplete || error != nil {
                self.lost()
            } else {
                self.receiveHeader()
            }
        }
    }

    private func receiveBody(_ length: Int) {
        guard length > 0 else { return receiveHeader() }
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, _ in
            guard let self, !self.closed else { return }
            guard let data, data.count == length else { return self.lost() }
            self.onReceive?(data)
            self.receiveHeader()
        }
    }

    private func lost() {
        guard !closed else { return }
        let callback = onClose
        close()
        callback?()
    }

    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 4
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcp)
        // Also directly between nearby devices, without a shared Wi-Fi network.
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// Finds a nearby opponent (same network, or directly via Wi-Fi/Bluetooth peer-to-peer) using Bonjour.
///
/// - Code game: the host advertises a service with the code in its name; the guest looks for exactly that one.
/// - Quick game: every device advertises and browses at the same time. Of two devices, the one with the
///   smaller ID connects to the other; the other one becomes the host.
final class NearbyFinder {
    enum Role { case host, guest }

    static let serviceType = "_creepsmash._tcp"
    private static var prefix: String { "CS\(NetMessage.protocolVersion)" }

    var onConnected: ((Transport, Role) -> Void)?
    var onError: ((String) -> Void)?
    /// Devices that would match but run another protocol version (they cannot play together):
    /// their versions, reported whenever the set changes. They are never connected to.
    var onOtherVersions: ((Set<Int>) -> Void)?
    /// Short technical status for the search screen (helps when nothing is found).
    var onStatus: ((String) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var accept: ((String) -> Bool)?
    /// Connection attempts by service name. A name is tried again once its attempt has failed.
    private var attempts: [String: StreamTransport] = [:]
    private var retryTimer: Timer?
    private var finished = false
    private var advertised = "–"
    private var found = 0
    /// What the search is for: kind "Q" (quick game) or "C" with the code. Names of other versions are
    /// recognized by this, so the player learns why nobody is found.
    private var wanted: (kind: String, code: String?) = ("Q", nil)
    private var otherVersions: Set<Int> = []

    /// Parts of a service name "CS<version>-<kind>-<id or code>" – the scheme of all versions so far.
    static func parse(_ name: String) -> (version: Int, kind: String, rest: String)? {
        let parts = name.split(separator: "-", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0].hasPrefix("CS"), let version = Int(parts[0].dropFirst(2)) else { return nil }
        return (version, parts[1], parts[2])
    }

    func host(code: String) {
        advertise(name: "\(Self.prefix)-C-\(code)")
    }

    func join(code: String) {
        let target = "\(Self.prefix)-C-\(code)"
        wanted = ("C", code)
        browse { name in name == target }
    }

    func quick() {
        let me = String(UInt32.random(in: .min ... .max), radix: 16)
        let quickPrefix = "\(Self.prefix)-Q-"
        wanted = ("Q", nil)
        advertise(name: quickPrefix + me)
        browse { name in
            guard name.hasPrefix(quickPrefix) else { return false }
            let other = String(name.dropFirst(quickPrefix.count))
            return other != me && me < other
        }
    }

    func stop() {
        finished = true
        retryTimer?.invalidate()
        retryTimer = nil
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        attempts.values.forEach { $0.close() }
        attempts.removeAll()
    }

    private func advertise(name: String) {
        do {
            let listener = try NWListener(using: StreamTransport.parameters)
            listener.service = NWListener.Service(name: name, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, !self.finished else { return connection.cancel() }
                self.attempt(connection, name: "in:\(connection.endpoint)", role: .host)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.advertised = "ok"
                case let .waiting(error):
                    self.advertised = "\(error)"
                    self.checkPermission(error)
                case let .failed(error):
                    self.fail(L("Network not available (\(error.localizedDescription))"))
                default:
                    break
                }
                self.reportStatus()
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            fail(L("Network not available (\(error.localizedDescription))"))
        }
    }

    private func browse(accept: @escaping (String) -> Bool) {
        self.accept = accept
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: StreamTransport.parameters)
        browser.browseResultsChangedHandler = { [weak self] _, _ in self?.connectToResults() }
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case let .waiting(error):
                self.checkPermission(error)
            case let .failed(error):
                self.fail(L("Search not possible (\(error.localizedDescription))"))
            default:
                break
            }
            self.reportStatus()
        }
        browser.start(queue: .main)
        self.browser = browser
        // Failed attempts are repeated as long as the other device is still visible.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.connectToResults()
        }
    }

    /// Connects to every matching service that has no running attempt yet.
    private func connectToResults() {
        guard !finished, let browser, let accept else { return }
        found = 0
        var versions: Set<Int> = []
        for result in browser.browseResults {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            if let other = Self.parse(name), other.version != NetMessage.protocolVersion, other.kind == wanted.kind,
               wanted.code == nil || other.rest == wanted.code {
                versions.insert(other.version)
                continue
            }
            guard accept(name) else { continue }
            found += 1
            guard attempts[name] == nil else { continue }
            attempt(NWConnection(to: result.endpoint, using: StreamTransport.parameters), name: name, role: .guest)
        }
        if versions != otherVersions {
            otherVersions = versions
            onOtherVersions?(versions)
        }
        reportStatus()
    }

    private func attempt(_ connection: NWConnection, name: String, role: Role) {
        let transport = StreamTransport(connection: connection)
        attempts[name] = transport
        transport.onClose = { [weak self, weak transport] in
            guard let self, let transport, self.attempts[name] === transport else { return }
            self.attempts[name] = nil
            self.reportStatus()
        }
        transport.onReady = { [weak self, weak transport] in
            guard let self, let transport, !self.finished else { return }
            self.attempts[name] = nil
            transport.onClose = nil
            self.stop()
            self.onConnected?(transport, role)
        }
        // An attempt that does not get through within a few seconds is given up and repeated.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak transport] in
            guard let self, let transport, !self.finished, self.attempts[name] === transport else { return }
            self.attempts[name] = nil
            transport.close()
            self.reportStatus()
        }
        reportStatus()
    }

    /// Without permission for the local network, iOS keeps the search waiting instead of failing.
    private func checkPermission(_ error: NWError) {
        // kDNSServiceErr_PolicyDenied
        if case let .dns(code) = error, code == -65570 {
            fail(L("CreepSmash may not use the local network. Allow it under Settings › Privacy & Security › Local Network › CreepSmash."))
        }
    }

    private func reportStatus() {
        guard !finished else { return }
        let search: String
        switch browser?.state {
        case .ready: search = "ok"
        case let .waiting(error): search = "\(error)"
        case nil: search = "–"
        default: search = "…"
        }
        onStatus?("visible: \(advertised) · search: \(search) · found: \(found) · connecting: \(attempts.count)")
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        stop()
        onError?(message)
    }
}
