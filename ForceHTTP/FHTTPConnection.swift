// managed by service

import Foundation
import Network

internal class FHTTPConnection {
    internal enum State {
        case inited
        case connecting
        case active
        case closing
        case closed
    }
    
    internal init(queue: DispatchQueue,
                scheme: FHTTPScheme,
                host: String,
                port: UInt16)
    {
        self.queue = queue
        self.scheme = scheme
        self.host = host
        self.port = port
        
        let nwHost = NWEndpoint.Host.name(host, nil)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let endPoint = NWEndpoint.hostPort(host: nwHost, port: nwPort)
        let parameters = NWParameters(tls: nil)
        
        self.connection = NWConnection(to: endPoint, using: parameters)
        
        self.state = .inited
                
        self.receiveBuffer = Data()
        self.isReceiveCompleted = false
    }
    
    deinit {
        if state != .closing && state != .closed {
            connection.forceCancel()
        }
    }
    
    internal let queue: DispatchQueue
    internal let connection: NWConnection
    internal private(set) var state: State
    
    internal let scheme: FHTTPScheme
    internal let host: String
    internal let port: UInt16
    
    internal var errorHandler: ((Error) -> Void)?
    
    internal func close(handler: @escaping () -> Void) {
        state = .closing
        
        session = nil
        errorHandler = nil
        
        connection.stateUpdateHandler = { (state) in
            switch state {
            case .cancelled:
                self.state = .closed
                self.connection.stateUpdateHandler = nil
                return handler()
            default:
                break
            }
        }
        connection.cancel()
    }
    
    internal func open(handler: @escaping (Error?) -> Void) {
        state = .connecting
        
        connection.stateUpdateHandler = { (state) in
            switch state {
            case .failed(let error):
                self.connection.stateUpdateHandler = nil
                handler(error)
            case .ready:
                self.connection.stateUpdateHandler = nil
                self.state = .active
                
                handler(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
    
    internal var error: Error? {
        switch connection.state {
        case .failed(let error):
            return error
        default:
            return nil
        }
    }
    
    internal func attachSession(_ session: FHTTPSession) {
        self.session = session
        session.onAttachConnection(self)
        
        sendRequestHeader(session: session)
    }
    
    private func detachSession(_ session: FHTTPSession) {
        precondition(session.state == .completed)
        
        self.session = nil
        session.onDetachConnection(self)
    }
    
    internal var session: FHTTPSession?
    
    internal func sendRequestHeader(session: FHTTPSession) {
        let data = session.onRequestHeaderSend()
        
        connection.send(content: data, completion: .contentProcessed({ (error) in
            self.receiveHeader(session: session, error: error)
        }))
    }
    
    internal func receiveHeader(session: FHTTPSession, error: Error?) {
        do {
            if let error = error {
                throw error
            }
            
            if let response = try self.tryParseResponse() {
                session.onResponseHeader(response)
                return
            }

            receive { (error) in
                self.receiveHeader(session: session, error: error)
            }
        } catch {
            self.errorHandler?(error)
        }
    }
    
    internal func receiveContent(session: FHTTPSession, error: Error?) {
        do {
            if let error = error {
                throw error
            }
            
            let length = session.response!.header.contentLength!

            if receiveBuffer.count >= length {
                let data = self.receiveBuffer[..<length]
                session.onResponseContent(data)
                detachSession(session)
                return
            }
            
            receive { (error) in
                self.receiveContent(session: session, error: error)
            }
        } catch {
            self.errorHandler?(error)
        }
    }
    
    private func receive(handler: @escaping (Error?) -> Void) {
        connection.receive(minimumIncompleteLength: 0,
                           maximumLength: 1024 * 1024)
        { (data, context, isComplete, error) in
            if let error = error {
                handler(error)
                return
            }
            if let data = data {
                self.receiveBuffer.append(data)
            }
            if isComplete {
                self.isReceiveCompleted = true
            }
            handler(nil)
        }
    }
    
    private(set) var receiveBuffer: Data
    private(set) var isReceiveCompleted: Bool
    
    private func tryParseResponse() throws -> FHTTPResponse? {
        if receiveBuffer.count > 1000 * 1000 {
            throw FHTTPError.tooLargeResponseHeader
        }
        
        let separatorData: Data = "\r\n\r\n".data(using: .utf8)!
        var index = 0
        while true {
            guard index + 4 <= receiveBuffer.count else {
                if isReceiveCompleted {
                    throw FHTTPError.noResponseHeader
                }
                
                return nil
            }
            
            if receiveBuffer[index..<index+4] == separatorData {
                let headerData = receiveBuffer[..<index]
                receiveBuffer.removeSubrange(..<(index+4))
                
                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    throw FHTTPError.invalidResponseHeader
                }

                guard let delimiterRange = headerString.range(of: "\r\n") else {
                    throw FHTTPError.invalidResponseHeader
                }
                
                let headLine = String(headerString[..<delimiterRange.lowerBound])
                let headParts = headLine.components(separatedBy: " ")
                guard headParts.count >= 3 else {
                    throw FHTTPError.invalidResponseHeader
                }
                
                guard let statusCode = Int(headParts[1]) else {
                    throw FHTTPError.invalidResponseHeader
                }
                
                let fieldsString = String(headerString[delimiterRange.upperBound...])
              
                return FHTTPResponse(statusCode: statusCode,
                                     header: FHTTPHeader(from: fieldsString),
                                     data: Data())
            }
            
            index += 1
        }
    }
}
