// running on service work queue
// manages connection pool in future
// pipelining is not implemented

import Foundation
import Network

public class FHTTPService {
    public static let shared: FHTTPService = .init()
    
    public init() {
        self.workQueue = DispatchQueue(label: "FHTTPService.workQueue")
    }
    
    deinit {
        connections.forEach {
            $0.connection.forceCancel()
        }
    }
    
    public let workQueue: DispatchQueue
    
    internal typealias Canceller = () -> Void
    
    internal func onSessionStart(_ session: FHTTPSession) {
        sessions.append(session)
        
        update()
    }
    
    internal func onSessionClose(_ session: FHTTPSession) {
        let connectionOrNone = session.connection
        
        sessions.removeAll { $0 === session }
        
        if let connection = connectionOrNone {
            onConnectionError(connection: connection, error: FHTTPError.connectionClosed)
        }
        
        update()
    }

    internal func onSessionReceiveContent(_ session: FHTTPSession) {
        precondition(session.state == .responseContentReceive)
        
        session.connection!.receiveContent(session: session,
                                           error: nil)
    }

    private func update() {
        sessions.forEach { session in
            switch session.state {
            case .connecting:
                openOrAttachConnection(session: session)
            default: break
            }
        }
        
        connections.forEach { connection in
            switch connection.state {
            case .connecting:
                let sessions = waitingSessions(for: connection)
                
                if sessions.count == 0 {
                    closeConnection(connection)
                    return
                }
            default: break
            }
        }
    }
    
    private func openOrAttachConnection(session: FHTTPSession) {
        let possibleConnections = self.connections
            .filter { session.isSameEndPoint($0) &&
                ($0.state == .connecting ||
                    $0.state == .active) }
        if possibleConnections.count == 0 {
            openConnection(request: session.request)
            return
        }
        
        let connectionOrNone = possibleConnections
            .first { $0.state == .active &&
                $0.session == nil }
        guard let connection = connectionOrNone else {
            return
        }
        
        connection.attachSession(session)
    }
    
    private func openConnection(request: FHTTPRequest) {
        let connection = FHTTPConnection(queue: workQueue,
                                         scheme: request.scheme,
                                         host: request.host,
                                         port: request.connectingPort)
        log("openConnection: \(connection.endPointString)")
        
        self.connections.append(connection)
        
        connection.open { (error) in
            if let error = error {
                self.onOpenConnectionError(connection: connection, error: error)
                return
            }
            
            self.update()
        }

        connection.errorHandler = { (error) in
            self.onConnectionError(connection: connection, error: error)
        }
    }
    
    private func onOpenConnectionError(connection: FHTTPConnection, error: Error) {
        let sessions = self.waitingSessions(for: connection)
        
        closeConnection(connection)
        
        sessions.forEach { session in
            session.onError(error)
        }
    }
    
    private func onConnectionError(connection: FHTTPConnection, error: Error) {
        let sessionOrNone = connection.session
        
        closeConnection(connection)
        
        if let session = sessionOrNone {
            session.onError(error)
        }
    }
    
    private func closeConnection(_ connection: FHTTPConnection) {
        log("closeConnection: \(connection.endPointString)")

        connection.close {
            self.connections.removeAll { $0 === connection }
        }
    }
    
    private func waitingSessions(for connection: FHTTPConnection) -> [FHTTPSession] {
        return self.sessions.filter {
            $0.state == .connecting &&
            $0.isSameEndPoint(connection)
        }
    }
    
    internal private(set) var sessions: [FHTTPSession] = []
    internal private(set) var connections: [FHTTPConnection] = []
    
    private func log(_ message: String) {
        print("[FHTTPService] \(message)")
    }
}
