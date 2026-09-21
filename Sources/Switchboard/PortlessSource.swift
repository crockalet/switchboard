// `~/.portless` is outside TCC-protected locations, so no capability is needed.

import Foundation

/// portless's own route table, as it writes it.
private struct PortlessRoute: Decodable {
    let hostname: String
    let port: Int
    /// `0` for a static alias; otherwise a live child process id.
    let pid: Int
}

/// Reads portless state off disk and probes each route for liveness.
public struct PortlessSource: Sendable {
    /// `~/.portless`, or wherever `PORTLESS_STATE_DIR` points.
    public let stateDirectory: URL

    public init(stateDirectory: URL? = nil) {
        if let stateDirectory {
            self.stateDirectory = stateDirectory
        } else if let override = ProcessInfo.processInfo.environment["PORTLESS_STATE_DIR"], !override.isEmpty {
            self.stateDirectory = URL(fileURLWithPath: override)
        } else {
            self.stateDirectory = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".portless", isDirectory: true)
        }
    }

    /// Whether the portless proxy itself is up, and on which port.
    public func proxyStatus() -> (port: Int, https: Bool, running: Bool)? {
        let dir = stateDirectory
        guard let pidText = try? String(contentsOf: dir.appendingPathComponent("proxy.pid"), encoding: .utf8),
              let pid = pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        let port = (try? String(contentsOf: dir.appendingPathComponent("proxy.port"), encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 443
        let https = (try? String(contentsOf: dir.appendingPathComponent("proxy.tls"), encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "1" } ?? true

        return (port, https, Self.isAlive(pid))
    }

    /// Every route portless knows, with liveness already resolved.
    public func services() -> [Service] {
        let routesURL = stateDirectory.appendingPathComponent("routes.json")
        guard let data = try? Data(contentsOf: routesURL),
              let routes = try? JSONDecoder().decode([PortlessRoute].self, from: data)
        else { return [] }

        let proxy = proxyStatus()

        return routes.map { route in
            // A real pid is a free liveness signal; an alias needs a port probe.
            let pid: pid_t? = route.pid > 0 ? pid_t(route.pid) : nil
            let status: ServiceStatus = {
                if let pid { return Self.isAlive(pid) ? .running : .stopped }
                return Self.isListening(port: route.port) ? .running : .stopped
            }()

            let scheme = (proxy?.https ?? true) ? "https" : "http"
            var url = URLComponents()
            url.scheme = scheme
            url.host = route.hostname
            if let proxyPort = proxy?.port, proxyPort != (scheme == "https" ? 443 : 80) {
                url.port = proxyPort
            }
            url.path = "/"

            return Service(
                id: "portless:\(route.hostname)",
                name: route.hostname.split(separator: ".").first.map(String.init) ?? route.hostname,
                url: url.url,
                port: route.port,
                pid: pid,
                origin: .portless,
                status: status,
                // Deliberately empty: only the companion knows how to restart it.
                actions: []
            )
        }
    }

    // MARK: - Probes

    /// `kill(pid, 0)` asks the kernel; `EPERM` still means the process exists.
    static func isAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// A short, non-blocking connect distinguishes bound from unbound.
    static func isListening(port: Int, timeout: TimeInterval = 0.12) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var flags = fcntl(fd, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, Int32(timeout * 1000)) > 0 else { return false }

        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return false }
        return error == 0
    }
}
