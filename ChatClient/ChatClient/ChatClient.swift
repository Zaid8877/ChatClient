//
//  ChatClient.swift
//  ChatClient
//
//  Created by zaidtayyab on 18/05/2018.
//  Copyright © 2018 Ingic. All rights reserved.
//

import Foundation
import UIKit


@objc
public protocol ChatClientDelegate: NSObjectProtocol {
    func subscriptionMessageReceived(channel: String, message: String)
    func socketDidDisconnect(client: ChatClient, error: Error?)
    func socketDidConnect(client: ChatClient)
}

@objc
public class ChatClient: NSObject, GCDAsyncSocketDelegate, ChatMessageReceivedDelegate {
    public typealias CompletionBlock = (NSArray) -> Void
    public weak var delegate: ChatClientDelegate?
    var socket: GCDAsyncSocket
    var separator: Data
    var parseManager: ChatResponseParser
    var completionBlocks: Array<CompletionBlock?>

    @objc public init(delegate: ChatClientDelegate?) {
        self.socket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
        self.separator = ChatClient.convertStringIntoData(str: "\r\n")!
        self.parseManager = ChatResponseParser(delegate: nil)
        self.delegate = delegate
        self.completionBlocks = Array<CompletionBlock>()

        super.init()

        self.socket.delegate = self
        self.parseManager.delegate = self
    }

    static func convertStringIntoData(str: String) -> Data? {
        if let data = str.data(using: String.Encoding.utf8) {

            return data
        }

        return nil
    }

    deinit {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }

    private func doDisconnect() {
        self.socket.disconnect()
        self.parseManager.reset()
        self.completionBlocks.removeAll()
    }

    @objc public func close() {
        self.doDisconnect()
    }

    @objc public func isConnected() -> Bool {
        return self.socket.isConnected
    }

    @objc public func connect(host: String, port: Int, pwd: String?) {
        // We might be using a new auth or channel, so let's disconnect if we are connected
        if self.socket.isConnected {
            self.doDisconnect()
        }

        debugPrint("CHAT: Attempting doConnect to \(host) \(port) \(String(describing: pwd))")

        do {
            try self.socket.connect(toHost: host, onPort: UInt16(port))

            if let actualPwd: String = pwd {
                if !actualPwd.isEmpty {
                    // At this point the socket is NOT connected.
                    // But I can start writing to it anyway!
                    // The library will queue all my write operations,
                    // and after the socket connects, it will automatically start executing my writes!

                    self.exec(args: ["auth", actualPwd], completion: nil)
                }
            }
        } catch {
            debugPrint("CHAT: Unable to connect")
        }
    }

    static func addStringToCommandArray(commandArray: inout Array<String>, str1: String) {
        commandArray.append("$\(str1.characters.count)\r\n")
        commandArray.append("\(str1)\r\n")
    }

    static func buildStringCommand(_ args: String...) -> Data {
        var commandArray = Array<String>()

        commandArray.append("*\(args.count)\r\n")
        for arg in args {
            addStringToCommandArray(commandArray: &commandArray, str1: arg)
        }

        debugPrint("CHAT: Command with \(commandArray.joined())")

        return ChatClient.convertStringIntoData(str: commandArray.joined())! as Data
    }

    // MARK: Caht functions

    @objc public func exec(command: String, completion: CompletionBlock?) {
        let components = command.components(separatedBy: [" "])

        self.exec(args: components, completion: completion)
    }

    @objc public func exec(args: Array<String>, completion: CompletionBlock?) {
        var commandArray = Array<String>()

        commandArray.append("*\(args.count)\r\n")
        for arg in args {
            ChatClient.addStringToCommandArray(commandArray: &commandArray, str1: arg)
        }

        debugPrint("CHAT: Command with \(commandArray.joined())")

        let data = ChatClient.convertStringIntoData(str: commandArray.joined())! as Data

        sendCommand(data, completion)
    }

    func sendCommand(_ data: Data, _ completion: CompletionBlock?) {
        // We create an array of completion blocks to call serially
        // as we get responses back from our Caht operations
        self.completionBlocks.append(completion)
        self.socket.write(data, withTimeout: -1, tag: 0)
        self.socket.readData(to: self.separator, withTimeout: -1, tag: 0)
    }

    // MARK: CocaAsyncSocket Callbacks

    @objc public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        guard let line: String = String(data: data, encoding: .utf8) else {
            return
        }
        let trimmedString: String = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        debugPrint("CHAT: Line from didReadData is \(trimmedString)")

        self.parseManager.parseLine(data: data)
        self.socket.readData(to: self.separator, withTimeout: -1, tag: 0)
    }

    @objc public func socket(_ sock: GCDAsyncSocket, didReadPartialDataOfLength partialLength: UInt, tag: Int) {
        debugPrint("CHAT: Got something")
    }

    @objc public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        debugPrint("CHAT: Cool, I'm connected! That was easy.");

        self.delegate?.socketDidConnect(client: self)
    }

    @objc public func socket(_ sock: GCDAsyncSocket, didConnectTo url: URL) {
        debugPrint("CHAT: Cool, I'm connected! That was easy.");
    }

    @objc public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        debugPrint("CHAT: Disconnected me: \(String(describing: err?.localizedDescription))");

        self.parseManager.reset()
        self.completionBlocks.removeAll()
        self.delegate?.socketDidDisconnect(client: self, error: err)
    }

    @objc public func socketDidCloseReadStream(_ sock: GCDAsyncSocket) {
        debugPrint("CHAT: socketDidCloseReadStream: Disconnecting so we can rerun our connection")

        self.doDisconnect()
    }

    // MARK: Parser

    func chatMessageReceived(results: NSArray) {
        // See if this is a subscription message - those get sent via delegate method
        if (results.count == 3 && results.firstObject as? String != nil) {
            let message = results.firstObject as! String

            if (message == "message") {
                debugPrint("CHAT: Sending message of \(results[2])");

                self.delegate?.subscriptionMessageReceived(channel: results[1] as! String,
                                                           message: results[2] as! String)

                return
            }
        }

        if (self.completionBlocks.count > 0) {
            if let completionBlock: CompletionBlock = self.completionBlocks.removeFirst() {
                completionBlock(results)
            }
        } else {
            debugPrint("No completion blocks to send message \(results)")
        }
    }
}
