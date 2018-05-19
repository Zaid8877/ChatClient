//
//  ChatClient.swift
//  ChatClient
//
//  Created by zaidtayyab on 18/05/2018.
//  Copyright © 2018 Ingic. All rights reserved.
//

import Foundation

protocol ChatMessageReceivedDelegate: NSObjectProtocol {
    func chatMessageReceived(results: NSArray)
}

protocol ChatParserInterface: NSObjectProtocol {
    func parseLine(data: Data, parserStack: inout Array<ChatParserInterface>, results: inout Array<Any?>)
}

struct ChatStringParserClassConstants {
    static let separatorString = "\r\n"
    static let errorDomain = "com.ingic.ChatError"
}

class ChatStringParser: NSObject, ChatParserInterface {
    var length: Int
    var value: String?

    init(length: Int) {
        self.length = length;
    }

    func parseLine(data: Data, parserStack: inout Array<ChatParserInterface>, results: inout Array<Any?>) {

        if let line : NSString = NSString(data: data as Data, encoding: String.Encoding.utf8.rawValue) {
            let separatorRange = line.range(of: ChatStringParserClassConstants.separatorString)

            if (separatorRange.location == NSNotFound) {
                return;
            }

            assert(self.length == separatorRange.location, "length mismatch");

            debugPrint("SOCKET: string \(line)")

            results.append(line.substring(to: separatorRange.location));
        }
    }
}

class ChatGenericParser: NSObject, ChatParserInterface {
    func parseLine(data: Data, parserStack: inout Array<ChatParserInterface>, results: inout Array<Any?>) {

        guard let line: NSString = NSString(data: data as Data, encoding: String.Encoding.utf8.rawValue) else {
            return
        }

        let separatorRange = line.range(of: ChatStringParserClassConstants.separatorString)

        if (separatorRange.location == NSNotFound) {
            return
        }

        let restOfLineRange = NSMakeRange(1, separatorRange.location - 1)
        let restOfLine: String = line.substring(with: restOfLineRange)
        let firstCharacter: Character = Character(UnicodeScalar(line.character(at: 0))!)

        switch (firstCharacter) {
        case "-".characters.first!:
            debugPrint("SOCKET: - -- \(restOfLine)");

            let error =
                NSError(domain: ChatStringParserClassConstants.errorDomain,
                        code: -1,
                        userInfo: ["message": restOfLine]);
            results.append(error)
        case ":".characters.first!:
            debugPrint("SOCKET: + -- \(restOfLine)");

            if let restOfLineInt = Int(restOfLine) {
                results.append(restOfLineInt)
            }
        case "+".characters.first!:
            debugPrint("SOCKET: + -- \(restOfLine)");

            results.append(restOfLine);
        case "$".characters.first!:
            debugPrint("SOCKET: $ -- \(restOfLine)");

            if let length = Int(restOfLine) {
                if (length < 0) {
                    results.append(nil);
                } else {
                    let stringParser = ChatStringParser(length: length)
                    parserStack.append(stringParser)
                }
            }
        case "*".characters.first!:
            debugPrint("SOCKET: * -- \(restOfLine)");

            if let length = Int(restOfLine) {
                for _ in 0..<length {
                    let genericParser = ChatGenericParser()
                    parserStack.append(genericParser);
                }
            }
            break;
        default:
            break;
        }
    }
}

class ChatResponseParser: NSObject {
    weak var delegate: ChatMessageReceivedDelegate?
    var parserStack: Array<ChatParserInterface>
    var results: Array<Any?>

    init(delegate: ChatMessageReceivedDelegate?) {
        self.delegate = delegate

        self.parserStack = Array<ChatParserInterface>()
        self.results = Array<Any?>()
    }

    func reset() {
        self.parserStack.removeAll()
        self.results.removeAll()
    }

    func parseLine(data: Data) {

        if (self.parserStack.count == 0) {
            self.parserStack.append(ChatGenericParser())
        }

        let parserInterface: ChatParserInterface = self.parserStack.last!
        self.parserStack.removeLast()

        parserInterface.parseLine(data: data, parserStack: &self.parserStack, results: &self.results)

        if (self.parserStack.count == 0) {
            let finalResults = Array<Any?>(self.results)
            
            self.delegate?.chatMessageReceived(results: finalResults as NSArray)
            self.results.removeAll()
        }
    }
}
