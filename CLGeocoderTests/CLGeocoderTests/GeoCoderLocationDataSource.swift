import Foundation
import CoreLocation
import RxSwift

final class GeoCoderLocationDataSource {
    enum Error: Swift.Error {
        case noPlacemarksFound, timeout, unknownCLError, denied
    }
    enum Accuracy {
        // https://en.wikipedia.org/wiki/Decimal_degrees
        case region, district, town, street, landParcel, door
        
        var decimals: Int {
            switch self {
            case .region: return 0
            case .district: return 1
            case .town: return 2
            case .street: return 3
            case .landParcel: return 4
            case .door: return 5
            }
        }
    }
    
    let cache: Cache? // we cache placemarks with coordinate as key
    private let geocoder: CLGeocoder
    private let queue: DispatchQueue // we use a serial queue for handling multiple requests
    private let semaphore: DispatchSemaphore // we use a semaphore to wait for request being processed
    private let responseTimeout = 2.5 // we set a watchdog for the requests

    private let serialScheduler: SchedulerType

    convenience init(accuracyForCaching: Accuracy = .landParcel) {
        self.init(
            cache: .init(locationCoordinateAccuracy: accuracyForCaching)
        )
    }
    
    init(geocoder: CLGeocoder = .init(),
         queue: DispatchQueue = .init(label: "\(GeoCoderLocationDataSource.self)-serial-queue", qos: .userInitiated),
         semaphore: DispatchSemaphore = .init(value: 1),
         cache: Cache?) {
        self.geocoder = geocoder
        self.queue = queue
        self.serialScheduler = SerialDispatchQueueScheduler(queue: queue,
                                                            internalSerialQueueName: queue.label)
        self.semaphore = semaphore
        self.cache = cache
    }
    
    // MARK: - LocationDataSource
    
    func geocode(with coordinate: LocationCoordinate2D) -> Single<CLPlacemark> {
        return self.reverseGeocodeCoordinate(coordinate)
            .map(self.map(placemarks:))
    }
    
    // MARK: - private
    
    private func reverseGeocodeCoordinate(_ coordinate: LocationCoordinate2D) -> Single<[CLPlacemark]> {
        let coreLocationCoordinate = map(coordinate: coordinate)

        return Single.create { single in
            self.semaphore.wait()

            // 1. check Cache for placemark
            if let cached = self.cache?.getCachedPlacemarks(coordinate: coordinate) {
                single(.success([cached]))
            } else {
                let handler: CLGeocodeCompletionHandler = { (placemarks, error) in
                    if let placemarks = placemarks {
                        single(.success(placemarks))
                    } else {
                        let err: Swift.Error = error ?? Error.unknownCLError
                        single(.error(err))
                    }
                }
                // 2. make call to CLGeocoder
                self.geocoder.reverseGeocodeLocation(coreLocationCoordinate,
                                                     completionHandler: handler)
            }

            return Disposables.create { [weak self] in
                self?.geocoder.cancelGeocode()
                self?.semaphore.signal()
            }
        }
        .debug()
        .subscribeOn(serialScheduler)
            // 3. set a timeout
        .timeout(responseTimeout, scheduler: MainScheduler.asyncInstance)
        .observeOn(serialScheduler)
            // 4. map error
        .catchError { [weak self] (error) -> Single<[CLPlacemark]> in
            guard let strongSelf = self else { return .error(Error.denied) }
            return .error(strongSelf.map(error: error))
        }
            // check if retry can help
//       .asObservable()
//        .retry(1, delay: 0.1) { [weak self] (error: Swift.Error) in
//            return self?.isRecoverable(error: error) == true
//        }.asSingle()
        .do(onSuccess: { [weak self] (placemarks) in
            // 5. Cache new value
            self?.cache?.cache(placemarks: placemarks, with: coordinate)
        })
    }

    private func isRecoverable(error: Swift.Error) -> Bool {
        guard let error = error as? Error else { return false }
        switch error {
        case .noPlacemarksFound,
             .timeout:
            return true
        case .unknownCLError,
             .denied:
            return false
        }
    }
    
    private func map(coordinate: LocationCoordinate2D) -> CLLocation {
        return CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude)
    }
    
    private func map(placemarks: [CLPlacemark]) throws -> CLPlacemark {
        guard let placemark = placemarks.first else {
            throw Error.noPlacemarksFound
        }
        return placemark
    }
    
    private func map(error: Swift.Error) -> Error {
        if error is RxError {
            return .timeout
        }
        guard let clError = error as? CLError else { return .unknownCLError }
        return map(error: clError)
    }
    
    private func map(error: CLError) -> Error {
        switch error.code {
        case .locationUnknown,
             .network,
             .geocodeFoundNoResult,
             .geocodeFoundPartialResult:
            return .noPlacemarksFound
        case .denied:
            return .denied
        case .geocodeCanceled:
            return .timeout
        case .deferredAccuracyTooLow,
             .deferredFailed,
             .deferredCanceled,
             .deferredDistanceFiltered,
             .deferredNotUpdatingLocation,
             .headingFailure,
             .rangingFailure,
             .rangingUnavailable,
             .regionMonitoringDenied,
             .regionMonitoringFailure,
             .regionMonitoringSetupDelayed,
             .regionMonitoringResponseDelayed:
            return .unknownCLError
        }
    }
}

struct LocationCoordinate2D: Codable {
    let latitude: Double
    let longitude: Double
}
