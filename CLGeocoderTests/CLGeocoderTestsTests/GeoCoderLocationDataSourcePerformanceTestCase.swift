import XCTest
import CoreLocation
import RxSwift
import RxBlocking
@testable import CLGeocoderTests

final class GeoCoderLocationDataSourcePerformanceTestCase: XCTestCase {
    typealias SUT = GeoCoderLocationDataSource
    
    struct TestDouble {
        private static var filename: String {
            //            return "geocoder.performance" // NOTE: performance tests with this json eventually throws error "Error Domain=kCLErrorDomain Code=2 "(null)""
            return "geocoder.performance.success"
        }
        let coordinates: [LocationCoordinate2D] = try! MockLoader.loadJSONFile(name: filename, type: [LocationCoordinate2D].self)
    }
    
    var sut: GeoCoderLocationDataSource!
    
    func testReverseGeocode() {
        let coordinate = TestDouble().coordinates.first!
        
        sut = GeoCoderLocationDataSource(cache: nil)
        // NOTE: deviation is extremly high (up to >500%), why does first request take so much longer then rest?
        measure {
            do {
                _ = try sut.geocode(with: coordinate).toBlocking().single()
            } catch {
                XCTFail("unexpected throw in reverseGeocode: \(error)")
            }
        }
    }
    
    func testReverseGeocodeCache() {
        let coordinates = TestDouble().coordinates
        var result: [CLPlacemark]?
        
        sut = GeoCoderLocationDataSource(accuracyForCaching: .landParcel)
        //measuring performance of batch reverse geocoding
        measure {
            sut.cache?.clear()
            do {
                result = try self.reverseGeocodeBatch(coordinates: coordinates)
            } catch {
                XCTFail("unexpected throw in reverseGeocode: \(error)")
            }
        }
        
        XCTAssert(result?.isEmpty == false, "reverse geocoding failed")
        XCTAssert(result?.filter { $0.postalCode == nil }.isEmpty == true, "country should not be empty")
        
        let expectedKeys: [String] = ["41.3853,2.1717", "41.3852,2.1717"]
        XCTAssert(sut.cache?.keys == expectedKeys, "caching keys mismatch: \(String(describing: sut.cache?.keys))")
    }
    
    private func reverseGeocodeBatch(coordinates: [LocationCoordinate2D]) throws -> [CLPlacemark]? {
        var result = [CLPlacemark]()
        try coordinates.forEach { coordinate in
            result.append(try sut.geocode(with: coordinate).toBlocking().single())
        }
        return result
    }
}
