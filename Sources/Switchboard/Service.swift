//
//  Service.swift
//  Switchboard
//

import Foundation

/// Where Switchboard learned about a service.
public enum ServiceOrigin: String, Codable, Sendable {
    /// Read straight out of `~/.portless/routes.json`. Always available.
    case portless
    /// Described in the companion CLI's config. Controllable.
    case companion
}

/// Whether a service is answering right now.
public enum ServiceStatus: String, Codable, Sendable {
    case running
    case stopped
    /// Known to exist, but nothing has probed it yet this refresh.
    case unknown
}

/// What Switchboard can do to a service.
///
/// The read-only path leaves this empty: reading portless's route table tells
/// you a service exists, not how to restart it. Only the companion, which owns
/// the config that names the command, fills these in.
public struct ServiceActions: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let start = ServiceActions(rawValue: 1 << 0)
    public static let stop = ServiceActions(rawValue: 1 << 1)
    public static let restart = ServiceActions(rawValue: 1 << 2)
}

/// One row in the command center.
public struct Service: Identifiable, Sendable, Equatable {
    public let id: String
    /// Display name. For a portless route this is the hostname's first label.
    public let name: String
    /// The URL a person would actually open, when there is one.
    public let url: URL?
    public let port: Int?
    /// The process behind it, when something knows. `nil` for a portless alias,
    /// whose route table entry carries `"pid": 0`.
    public let pid: pid_t?
    public let origin: ServiceOrigin
    public var status: ServiceStatus
    public let actions: ServiceActions

    public init(
        id: String,
        name: String,
        url: URL? = nil,
        port: Int? = nil,
        pid: pid_t? = nil,
        origin: ServiceOrigin,
        status: ServiceStatus = .unknown,
        actions: ServiceActions = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.port = port
        self.pid = pid
        self.origin = origin
        self.status = status
        self.actions = actions
    }
}
