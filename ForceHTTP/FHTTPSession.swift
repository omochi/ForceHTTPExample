// running on service work queue
// access from any queue

import Foundation

public class FHTTPSession {
    public enum State {
        case inited
        case connecting
        case connected
        case requestHeaderSent
        case responseHeaderReceived
        case responseContentReceive
        case completed
        case failed
        case closed
    }
   
    public let service: FHTTPService
    private let workQueue: DispatchQueue
    public let callbackQueue: DispatchQueue
    
    public let request: FHTTPRequest
    
    public private(set) var state: State
    
    private typealias Handler = (FHTTPResponse?, Error?) -> Void
    private var handler: Handler?
    
    internal private(set) var response: FHTTPResponse?
    
    internal init(service: FHTTPService,
                  request: FHTTPRequest)
    {
        self.service = service
        self.workQueue = service.workQueue
        self.callbackQueue = DispatchQueue.main
        self.request = request
        self.state = .inited
    }
    
    deinit {
        _close()
    }
    
    public func start(handler: @escaping (FHTTPResponse?, Error?) -> Void) {
        workQueue.sync {
            precondition(state == .inited)
            
            self.handler = handler
            state = .connecting
            
            service.onSessionStart(self)
        }
    }

    public func close() {
        workQueue.sync {
            _close()
        }
    }
    private func _close() {
        state = .closed
        
        service.onSessionClose(self)
        
        self.handler = nil
    }
    
    
    internal var connection: FHTTPConnection? {
        return service.connections.first { $0.session === self }
    }
    
    internal func isSameEndPoint(_ connection: FHTTPConnection) -> Bool {
        return request.scheme == connection.scheme &&
            request.host == connection.host &&
            request.connectingPort == connection.port
    }
    
    internal func onAttachConnection(_ connection: FHTTPConnection) {
        print("onAttachConnection: \(connection.endPointString)")
        precondition(state == .connecting)
        
        state = .connected
    }

    internal func onRequestHeaderSend() -> Data {
        print("onRequestHeaderSend")
        var host: String = request.host
        if let port = request.specifiedPort {
            host += ":" + "\(port)"
        }
        
        var lines = [String]()
        lines.append("\(request.method) \(request.path) HTTP/1.1")
        lines.append("Host: \(host)")
        lines.append("Connection: close")
        lines.append("User-Agent: ForthHTTP")
        lines += ["", ""]
        
        let header: String = lines.joined(separator: "\r\n")
        let data = header.data(using: String.Encoding.utf8)!
        
        self.state = .requestHeaderSent
        
        return data
    }
    
    internal func onResponseHeader(_ response: FHTTPResponse) {
        print("onResponseHeader")
        self.response = response
        self.state = .responseHeaderReceived
        
        self.state = .responseContentReceive
        self.service.onSessionReceiveContent(self)
    }
    
    internal func onResponseContent(_ data: Data) {
        print("onResponseContent")
        self.response!.data = data
        self.state = .completed
    }
    
    internal func onDetachConnection(_ connection: FHTTPConnection) {
        print("onDetachConnection: \(connection.endPointString)")

        precondition(state == .completed)
        
        callbackQueue.async {
            let handler = self.workQueue.sync {
                return self.handler
            }
            
            handler?(self.response!, nil)
        }
    }
    
    internal func onError(_ error: Error) {
        state = .failed
        
        callbackQueue.async {
            let handler = self.workQueue.sync {
                return self.handler
            }
            
            handler?(nil, error)
            
            self.close()
        }
    }
    
}
