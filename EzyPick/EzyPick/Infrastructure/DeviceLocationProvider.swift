import CoreLocation

/// Answers the one question CoreLocation is here for: where is the diner standing right now?
///
/// Kept behind `CurrentLocationProvider` so the use cases and the repository can be exercised with
/// a fixed coordinate. Coarse on purpose: street accuracy costs battery and standing-still time.
///
/// - Important: Resuming a continuation twice traps the process, so ``finish(_:)`` is the only
///   place that resumes, on every path including a denial that arrives before `requestLocation()`
///   returns, and it takes the continuation out from under the lock. CoreLocation calls the
///   delegate on the manager's own queue while `currentCoordinate()` may be awaited from anywhere,
///   hence a lock rather than an actor.
nonisolated final class DeviceLocationProvider: NSObject, CurrentLocationProvider, @unchecked Sendable {
    /// How long a diner will wait to be found before the app should say something instead.
    private static let patience: Duration = .seconds(10)

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var pending: CheckedContinuation<Coordinate, Error>?
    private var countdown: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Where the diner is, or why the app could not find out.
    ///
    /// - Note: Asks for when-in-use authorisation first if it never has; the answer arrives on the
    ///   delegate, so the request is parked until it does and a refusal ends it there.
    func currentCoordinate() async throws -> Coordinate {
        try await withCheckedThrowingContinuation { continuation in
            begin(continuation)
        }
    }

    private func begin(_ continuation: CheckedContinuation<Coordinate, Error>) {
        lock.lock()
        guard pending == nil else {
            lock.unlock()
            // One at a time, never queued. A search does ask twice, but in sequence: the view
            // model for the origin it shows, then the repository to centre the request. Two at
            // once means a caller started a second search over the top of the first.
            continuation.resume(throwing: LocationError.unavailable)
            return
        }
        pending = continuation
        countdown = Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(LocationError.timedOut))
        }
        lock.unlock()

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            manager.requestLocation()
        }
    }

    /// Resumes the waiting call, once and only once: whoever reaches the continuation first takes
    /// it and everyone after finds nil, which makes a late delegate callback harmless.
    private func finish(_ result: Result<Coordinate, Error>) {
        lock.lock()
        let waiting = pending
        pending = nil
        let timer = countdown
        countdown = nil
        lock.unlock()

        timer?.cancel()
        waiting?.resume(with: result)
    }

    private var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending != nil
    }
}

/// `nonisolated` for the same reason the class is: the target compiles with main actor isolation by
/// default, and CoreLocation calls these back without one.
nonisolated extension DeviceLocationProvider: CLLocationManagerDelegate {
    /// Also fires once when the delegate is first set, hence the guard on somebody waiting.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isWaiting else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else {
            finish(.failure(LocationError.unavailable))
            return
        }
        finish(.success(Coordinate(latitude: fix.coordinate.latitude,
                                   longitude: fix.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let cause: LocationError = (error as? CLError)?.code == .denied ? .denied : .unavailable
        finish(.failure(cause))
    }
}

/// What can go wrong when the app tries to work out where the diner is. Every message is read by
/// someone standing on a footpath, so each says what happened and what they can do next.
enum LocationError: LocalizedError, Equatable {
    /// Location is switched off for this app, or the device will not allow it at all.
    case denied
    /// The device could not produce a fix.
    case unavailable
    /// The fix did not arrive in the time a person is willing to stand still for.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .denied: "Ezypick can't see where you are."
        case .unavailable: "Your location didn't come through."
        case .timedOut: "Finding you is taking longer than it should."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .denied:
            "Turn Location on for Ezypick in Settings, then start the search again."
        case .unavailable:
            "Step outside or somewhere with a clearer view of the sky, then try again."
        case .timedOut:
            "Try again in a moment. Moving closer to a window helps if you're indoors."
        }
    }
}
