//
//  CompanionClient.swift
//  Switchboard
//
//  The controllable half. Everything that runs a command lives behind this
//  HTTP boundary, in a CLI the user installs separately, because the reviewed
//  bundle must not be the thing that executes user-supplied strings.
//

import Foundation

/// The companion's wire shape for one service.
private struct CompanionService: Decodable {
    let id: String
    let name: String
    let url: String?
    let port: Int?
    let pid: Int?
    let status: String
    let actions: [String]
}

private struct CompanionList: Decodable {
    let services: [CompanionService]
}

private struct CompanionLogs: Decodable {
    let id: String
    let path: String?
    let lines: [String]
}

private struct CompanionResult: Decodable {
    let ok: Bool
    let message: String?
}

/// Why the companion could not be reached, in words a settings pane can show.
public enum CompanionError: Error, Sendable {
    case notInstalled
    case refused(String)
}

/// Talks to `switchboard-agent` over loopback. Covered by `network-client`.
public struct CompanionClient: Sendable {
    public static let defaultPort = 7878

    public let baseURL: URL
    private let session: URLSession

    public init(port: Int = CompanionClient.defaultPort) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let configuration = URLSessionConfiguration.ephemeral
        // The companion is on loopback. If it does not answer in well under a
        // second it is not running, and the shelf should not wait on it.
        configuration.timeoutIntervalForRequest = 1.5
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /// True when the companion answers its health probe.
    public func isReachable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/health"))
        request.httpMethod = "GET"
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }

    /// Every service the companion's config describes.
    public func services() async throws -> [Service] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/services"))
        request.httpMethod = "GET"

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw CompanionError.notInstalled
        }

        let list = try JSONDecoder().decode(CompanionList.self, from: data)
        return list.services.map { entry in
            var actions: ServiceActions = []
            if entry.actions.contains("start") { actions.insert(.start) }
            if entry.actions.contains("stop") { actions.insert(.stop) }
            if entry.actions.contains("restart") { actions.insert(.restart) }

            return Service(
                id: "companion:\(entry.id)",
                name: entry.name,
                url: entry.url.flatMap(URL.init(string:)),
                port: entry.port,
                pid: entry.pid.map(pid_t.init),
                origin: .companion,
                status: ServiceStatus(rawValue: entry.status) ?? .unknown,
                actions: actions
            )
        }
    }

    /// The tail of one service's log. `path` is nil when the agent could not
    /// work out where the service logs, which is a real answer worth showing.
    public func logs(for id: String, lines: Int = 200) async throws -> (path: String?, lines: [String]) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/services/\(id)/logs"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "lines", value: String(lines))]
        guard let url = components?.url else { throw CompanionError.notInstalled }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw CompanionError.notInstalled
        }

        let decoded = try JSONDecoder().decode(CompanionLogs.self, from: data)
        return (decoded.path, decoded.lines)
    }

    /// Start, stop or restart. `id` is the companion-side id, without the
    /// `companion:` prefix Switchboard adds for its own row identity.
    public func perform(_ action: String, on id: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/services/\(id)/\(action)"))
        request.httpMethod = "POST"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CompanionError.notInstalled
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let decoded = try? JSONDecoder().decode(CompanionResult.self, from: data)
            throw CompanionError.refused(decoded?.message ?? "The companion refused the request.")
        }
    }
}
