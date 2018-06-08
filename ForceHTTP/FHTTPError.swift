public enum FHTTPError : Error, CustomStringConvertible {
    case tooLargeResponseHeader
    case noResponseHeader
    case invalidResponseHeader
    case responseHasNoContentLength
    case connectionClosed
    
    public var description: String {
        switch self {
        case .tooLargeResponseHeader:
            return "response header is too large"
        case .noResponseHeader:
            return "no response header"
        case .invalidResponseHeader:
            return "response header is invalid format"
        case .responseHasNoContentLength:
            return "response header has no content length"
        case .connectionClosed:
            return "connection closed"
        }
    }
}
