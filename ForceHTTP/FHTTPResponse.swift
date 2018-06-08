import Foundation

public struct FHTTPResponse {
    public var statusCode: Int
    public var header: FHTTPHeader
    public var data: Data
}
