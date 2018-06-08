import Foundation

public struct FHTTPForm {
    public struct Entry {
        public var name: String
        public var value: String
        
        public init(name: String,
                    value: String)
        {
            self.name = name
            self.value = value
        }
    }
    
    public init() {
        self.entries = []
    }
    
    public var entries: [Entry]
    
    public static let contentType: String = "application/x-www-form-urlencoded"
    
    public func postBody() -> Data {
        var entryStrs: [String] = []
        
        entries.forEach { entry in
            let nameEscaped = entry.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            let valueEscaped = entry.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            
            entryStrs.append(nameEscaped + "=" + valueEscaped)
        }
        
        let dataStr = entryStrs.joined(separator: "&")
        
        return dataStr.data(using: .utf8)!
    }
}
