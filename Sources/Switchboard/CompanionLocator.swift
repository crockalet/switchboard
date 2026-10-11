//
//  CompanionLocator.swift
//  Switchboard
//

import Foundation

/// Where the companion listens and the token it expects.
public struct CompanionEndpoint: Equatable, Sendable {
    public var port: Int
    public var token: String?

    public init(port: Int = CompanionLocator.defaultPort, token: String? = nil) {
        self.port = port
        self.token = token
    }
}

/// Finds the companion's port in the companion's own config, so the two halves
/// cannot disagree about it and nobody has to type it twice.
public enum CompanionLocator {
    public static let defaultPort = 7878

    private struct AgentConfig: Decodable {
        let port: Int?
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/switchboard", isDirectory: true)
    }

    /// Read on every refresh, so editing the config and restarting the agent
    /// is all it takes.
    static func endpoint() -> CompanionEndpoint {
        CompanionEndpoint(port: port(), token: token())
    }

    /// The configured port, or the default when the companion is not installed.
    static func port() -> Int {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("services.json")),
              let config = try? JSONDecoder().decode(AgentConfig.self, from: data),
              let port = config.port,
              (1...65535).contains(port)
        else { return defaultPort }
        return port
    }

    /// Written by the agent when it first serves; nil until then.
    static func token() -> String? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("token"), encoding: .utf8)
        else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
