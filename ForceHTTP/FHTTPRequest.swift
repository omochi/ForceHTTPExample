public struct FHTTPRequest {
    public var url: URL
    public var method: FHTTPMethod = FHTTPMethod.get
    
    public init(url: URL) {
        self.url = url
    }
    
    public func session(service: FHTTPService = FHTTPService.shared) -> FHTTPSession
    {
        return FHTTPSession(service: service, request: self)
    }

    internal var scheme: FHTTPScheme {
        guard let schemeStr = url.scheme else {
            fatalError("invalid URL: no scheme")
        }
        guard let scheme = FHTTPScheme(rawValue: schemeStr) else {
            fatalError("invalid URL: unsupported scheme (\(schemeStr))")
        }
        return scheme
    }
    
    internal var host: String {
        guard let host = url.host else {
            fatalError("invalid URL: no host")
        }
        return host
    }
    
    internal var specifiedPort: UInt16? {
        guard let portInt = url.port else {
            return nil
        }
        
        guard let port = UInt16(exactly: portInt) else {
            fatalError("invalid port: \(portInt)")
        }
        return port
    }

    internal var connectingPort: UInt16 {
        return specifiedPort ?? scheme.defaultPort
    }
    
    internal var path: String {
        var path: String = url.path
        if path == "" {
            path = "/"
        }
        
        if let query = url.query {
            path += "?" + query
        }
        
        return path
    }
}
