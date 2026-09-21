//
//  CompanionLocator.swift
//  Switchboard
//

import Foundation

/// Finds the companion's port in the companion's own config, so the two halves
/// cannot disagree about it and nobody has to type it twice.
enum CompanionLocator {
    static let defaultPort = 7878

    private struct AgentConfig: Decodable {
        let port: Int?
    }

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/switchboard/services.json")
    }

    /// The configured port, or the default when the companion is not installed.
    static func port() -> Int {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AgentConfig.self, from: data),
              let port = config.port,
              (1...65535).contains(port)
        else { return defaultPort }
        return port
    }
}
