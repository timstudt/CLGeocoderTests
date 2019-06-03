import Foundation
import XCTest

// MARK: - MockLoader

final class MockLoader: NSObject {
    class func jsonDataNamed(_ name: String) -> Data {
        let bundle = Bundle(for: object_getClass(self)!)
        let path = bundle.path(forResource: name, ofType: "json")!
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            print("\nError loading json at: \(path)\n")
        }
        return (try! Data(contentsOf: url))
    }

    class func loadJSONFile<T>(name: String, type: T.Type) throws -> T where T: Swift.Decodable {
        let data = MockLoader.jsonDataNamed(name)
        return try JSONDecoder().decode(type, from: data)
    }
    
    enum `Error`: Swift.Error {
        case invalidEncoding
    }
}


// MARK: - Misc

private func defaultError() -> NSError {
    return NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
}
