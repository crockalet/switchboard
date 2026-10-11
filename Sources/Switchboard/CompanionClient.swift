// Command execution stays behind the companion's HTTP boundary: the reviewed
// bundle must not run user-supplied strings.

import Foundation

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

/// Why the companion could not be reached.
public enum CompanionError: Error, Sendable {
    case notInstalled
    /// The agent is up but does not accept this token.
    case unauthorized
    case refused(String)
}

/// Talks to `switchboard-agent` over loopback. Covered by `network-client`.
public struct CompanionClient: Sendable {
    /// A custom header also makes a browser preflight, which the agent never answers.
    static let tokenHeader = "X-Switchboard-Token"

    public let endpoint: CompanionEndpoint
    public let baseURL: URL
    private let session: URLSession

    public init(endpoint: CompanionEndpoint = CompanionEndpoint()) {
        self.endpoint = endpoint
        self.baseURL = URL(string: "http://127.0.0.1:\(endpoint.port)")!
        let configuration = URLSessionConfiguration.ephemeral
        // Loopback: if the companion does not answer quickly, it is not running.
        configuration.timeoutIntervalForRequest = 1.5
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    private func makeRequest(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = endpoint.token {
            request.setValue(token, forHTTPHeaderField: Self.tokenHeader)
        }
        return request
    }

    private static func checkAuthorized(_ response: URLResponse) throws {
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw CompanionError.unauthorized }
    }

    /// Every service the companion's config describes.
    public func services() async throws -> [Service] {
        let request = makeRequest(baseURL.appendingPathComponent("v1/services"), method: "GET")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CompanionError.notInstalled
        }
        try Self.checkAuthorized(response)

        let list = try JSONDecoder().decode(CompanionList.self, from: data)
        return list.services.compactMap { entry -> Service? in
            // A pid out of pid_t's range skips the row rather than trapping.
            var pid: pid_t?
            if let raw = entry.pid {
                guard let exact = pid_t(exactly: raw) else { return nil }
                pid = exact
            }
            var actions: ServiceActions = []
            if entry.actions.contains("start") { actions.insert(.start) }
            if entry.actions.contains("stop") { actions.insert(.stop) }
            if entry.actions.contains("restart") { actions.insert(.restart) }

            return Service(
                id: "companion:\(entry.id)",
                name: entry.name,
                url: entry.url.flatMap(URL.init(string:)),
                port: entry.port,
                pid: pid,
                origin: .companion,
                status: ServiceStatus(rawValue: entry.status) ?? .unknown,
                actions: actions
            )
        }
    }

    /// The tail; `path` is nil when the agent cannot identify the service's log.
    public func logs(for id: String, lines: Int = 200) async throws -> (path: String?, lines: [String]) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/services/\(id)/logs"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "lines", value: String(lines))]
        guard let url = components?.url else { throw CompanionError.notInstalled }

        let request = makeRequest(url, method: "GET")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CompanionError.notInstalled
        }
        try Self.checkAuthorized(response)

        let decoded = try JSONDecoder().decode(CompanionLogs.self, from: data)
        return (decoded.path, decoded.lines)
    }

    /// Start, stop or restart; `id` is companion-side, without `companion:`.
    public func perform(_ action: String, on id: String) async throws {
        let request = makeRequest(baseURL.appendingPathComponent("v1/services/\(id)/\(action)"), method: "POST")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CompanionError.notInstalled
        }
        try Self.checkAuthorized(response)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let decoded = try? JSONDecoder().decode(CompanionResult.self, from: data)
            throw CompanionError.refused(decoded?.message ?? "The companion refused the request.")
        }
    }
}
