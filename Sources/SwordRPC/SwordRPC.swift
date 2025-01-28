//
//  SwordRPC.swift
//  SwordRPC
//
//  Created by Alejandro Alonso
//  Copyright © 2017 Alejandro Alonso. All rights reserved.
//

import Combine
import Foundation
import os.log

public class SwordRPC {
    // MARK: App Info

    public let appId: String

    // MARK: Technical stuff

    let pid: Int32
    var client: ConnectionClient?
    let worker: DispatchQueue
    var log: Logger
    let currentPresence = CurrentValueSubject<RichPresence?, Never>(nil)
    var presenceUpdater: AnyCancellable!

    // MARK: Presence-related metadata

    var presence: RichPresence?

    // MARK: Event Handlers

    public weak var delegate: SwordRPCDelegate?

    public init(appId: String) {
        self.appId = appId

        pid = ProcessInfo.processInfo.processIdentifier
        log = Logger(subsystem: "space.joscomputing.swordrpc.\(pid)", category: "rpc")
        worker = DispatchQueue(
            label: "space.joscomputing.swordrpc.\(pid)",
            qos: .userInitiated
        )
    }

    /// Connects to a Discord client to serve RPC.
    public func connect() {
        let tempDir = FileManager.default.temporaryDirectory.path

        for ipcPort in 0 ..< 10 {
            let socketPath = tempDir + "/discord-ipc-\(ipcPort)"
            let localClient = ConnectionClient(pipe: socketPath)
            do {
                try localClient.connect()

                // Set handlers
                localClient.textHandler = handleEvent
                localClient.disconnectHandler = handleEvent

                client = localClient
                // Attempt handshaking
                try handshake()
            } catch {
                // If an error occurrs, we should not log it.
                // We must iterate through all 10 ports before logging.
                continue
            }

            subscribe(.join)
            subscribe(.spectate)
            subscribe(.joinRequest)
            return
        }

        print("[SwordRPC] Discord not detected")
    }

    /// Disconnects from the connected Discord client.
    /// If SwordRPC is not currently connected, this performs nothing.
    public func disconnect() {
        // We only need to clean up if our client is present and connected.
        guard let client else {
            return
        }

        // Clear presence.
        clearPresence()
        client.close()
        self.client = nil
    }

    /// Replies to an activity join request.
    /// - Parameters:
    ///   - user: The user making the request
    ///   - reply: Whether to accept or decline the request.
    public func reply(to user: PartialUser, with reply: JoinReply) {
        let type: CommandType

        switch reply {
        case .yes:
            type = .sendActivityJoinInvite
        case .ignore, .no:
            type = .closeActivityJoinRequest
        }

        // We must give Discord the requesting user's ID to handle.
        let command = Command(cmd: type, args: [
            "user_id": .string(user.userId),
        ])

        try? send(command)
    }
}
