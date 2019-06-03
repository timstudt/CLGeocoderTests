import Foundation
import CoreLocation
import RxSwift

protocol GeoCoderLocationCachable {
    var keys: [String] { get }
    func getCachedPlacemarks(coordinate: LocationCoordinate2D) -> CLPlacemark?
    func cache(placemarks: [CLPlacemark], with coordinate: LocationCoordinate2D)
    func clear()
}

extension GeoCoderLocationDataSource {
    final class Cache {
        typealias `Type` = NSCache<NSString, CLPlacemark>
        
        private(set) var keys: [String] = .init()
        
        private let cache: Type?
        private let coordinateFormatter: NumberFormatter
        
        init(cache: Type? = .init(),
             coordinateFormatter: NumberFormatter = .init(),
             locationCoordinateAccuracy: Accuracy) {
            self.cache = cache
            self.coordinateFormatter = coordinateFormatter
            self.coordinateFormatter.maximumFractionDigits = locationCoordinateAccuracy.decimals
        }
        
        private func cacheKey(for coordinate: LocationCoordinate2D) -> String {
            let latitude: String = coordinateFormatter.string(from: NSNumber(value: coordinate.latitude)) ?? "\(coordinate.latitude)"
            let longitude: String = coordinateFormatter.string(from: NSNumber(value: coordinate.longitude)) ?? "\(coordinate.longitude)"
            return "\(latitude),\(longitude)"
        }
    }
}

extension GeoCoderLocationDataSource.Cache: GeoCoderLocationCachable {
    func getCachedPlacemarks(coordinate: LocationCoordinate2D) -> CLPlacemark? {
        let key = cacheKey(for: coordinate)
        if let cachedPlacemark = cache?.object(forKey: key as NSString) {
            return cachedPlacemark
        }
        return nil
    }
    
    func cache(placemarks: [CLPlacemark], with coordinate: LocationCoordinate2D) {
        guard let placemark = placemarks.first else { return }
        let key = cacheKey(for: coordinate)
        if cache?.object(forKey: key as NSString) == nil {
            keys.append(key)
            cache?.setObject(placemark, forKey: key as NSString)
        }
    }
    
    func clear() {
        cache?.removeAllObjects()
        keys.removeAll()
    }
}
