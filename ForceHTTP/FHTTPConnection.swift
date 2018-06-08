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
        
        var tlsOptions: NWProtocolTLS.Options?
        if scheme == .https {
            tlsOptions = NWProtocolTLS.Options()
//            
//            sec_protocol_options
//            tlsOptions!.securityProtocolOptions
        }
        let parameters = NWParameters(tls: tlsOptions)
        
        self.connection = NWConnection(to: endPoint, using: parameters)
        
        self.state = .inited
        
        self.isReceiving = false
        self.receiveBuffer = Data()
        self.isReceiveCompleted = false
        
        self.isReceiveLooping = false
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
    
    private var isReceiving: Bool
    private var i = 0
    
    private var isReceiveLooping: Bool
    
    private(set) var receiveBuffer: Data
    private(set) var isReceiveCompleted: Bool
    
    
    
    internal var endPointString: String {
        var ret = scheme.rawValue + "://" + host
        
        if port != scheme.defaultPort {
            ret += ":" + String(port)
        }
        
        return ret
    }
    
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
        do {
            let data = try session.onRequestHeaderSend()
            
            print(String(data: data, encoding: .utf8))
            
            connection.send(content: data, completion: .contentProcessed({ (error) in
                switch session.state {
                case .requestBodySend:
                    self.sendBody(session: session, error: error)
                case .responseHeaderReceive:
                    self.receiveLoop(error: error)
                default:
                    preconditionFailure()
                }
            }))
        } catch {
            errorHandler?(error)
            return
        }
    }
    
    private func sendBody(session: FHTTPSession, error: Error?) {
        do {
            if let error = error {
                throw error
            }
            
            guard let chunk = session.onRequestBodySend() else {
                self.receiveLoop(error: nil)
                return
            }
            
            print(String(data: chunk, encoding: .utf8))
            
            connection.send(content: chunk, completion: .contentProcessed({ (error) in
                self.sendBody(session: session, error: error)
            }))
        } catch {
            errorHandler?(error)
            return
        }
    }
    
    internal func receiveLoop(error: Error?) {
        if isReceiveLooping { return }
        isReceiveLooping = true
        _receiveLoop(error: error)
    }
    
    private func _receiveLoop(error: Error?) {
        precondition(isReceiveLooping)
        
        do {
            if let error = error {
                throw error
            }
            
            if let session = self.session {
                while true {
                    var cont = false
                    
                    switch session.state {
                    case .responseHeaderReceive:
                        cont = try readHeader(session: session)
                    case .responseHeaderReceived:
                        isReceiveLooping = false
                        return
                    case .responseBodyReceive:
                        try receiveBody(session: session)
                    default:
                        preconditionFailure()
                    }
                    
                    if !cont {
                        break
                    }
                }
            } else {
                if receiveBuffer.count > 0 {
                    throw FHTTPError.protocolViolation
                }
            }
            
            if isReceiveCompleted {
                throw FHTTPError.connectionClosed
            }
            
            let maximumLength = 1024 * 1024
            let captureIndex = self.i
            self.i += 1
            print("receive \(captureIndex)")
            connection.receive(minimumIncompleteLength: 0,
                               maximumLength: maximumLength)
            { (data, context, isCompleted, error) in
                print("receive cb \(captureIndex), \(data?.count)")
                
                if let error = error {
                    self._receiveLoop(error: error)
                    return
                }
                if let data = data {
                    self.receiveBuffer.append(data)
                }
                if isCompleted {
                    self.isReceiveCompleted = true
                }
                
                self._receiveLoop(error: nil)
            }
        } catch {
            isReceiveLooping = false
            
            errorHandler?(error)
        }
    }

    typealias KeepReading = Bool
    
    private func readHeader(session: FHTTPSession) throws -> KeepReading {
        guard let response = try self.tryParseResponse() else {
            return false
        }

        session.onResponseHeader(response)
        return true
    }
    
    private func receiveBody(session: FHTTPSession) throws {
        let length = session.response!.header.contentLength!
        
        if receiveBuffer.count < length {
            return
        }
        
        let data = read(length)
        
        session.onResponseBody(data)
        detachSession(session)
    }
    
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
                let headerData = read(index)
                _ = read(4)

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
                let statusMessage = headParts[2...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                
                let fieldsString = String(headerString[delimiterRange.upperBound...])
              
                return FHTTPResponse(statusCode: statusCode,
                                     statusMessage: statusMessage,
                                     header: FHTTPHeader(from: fieldsString),
                                     data: Data())
            }
            
            index += 1
        }
    }
    
    private func read(_ size: Int) -> Data {
        let ret = receiveBuffer[..<size]
        receiveBuffer.removeSubrange(..<size)
        return ret
    }
}
