import CoreLocation

/// Answers the one question CoreLocation is here for: where is the diner standing right now?
///
/// The app's only CoreLocation dependency, kept behind `CurrentLocationProvider` so the use cases
/// and the places repository never import it and can be exercised with a fixed coordinate instead.
///
/// One `requestLocation()` rather than continuous updates: the app asks once, when a search starts,
/// and the walk it is planning does not move far enough while a few questions are answered to be
/// worth tracking. Accuracy is deliberately coarse for the same reason, and a coarse fix comes back
/// sooner, which is the part the diner feels.
///
/// - Important: the waiting call is resumed exactly once on every path, including a denial and a
///   failure that arrives before `requestLocation()` even returns. Resuming a continuation twice
///   traps the process, so ``finish(_:)`` is the only place that resumes and it takes the
///   continuation out from under the lock, leaving nil behind.
///
/// `CLLocationManager` calls its delegate on the queue the manager was created on, while
/// `currentCoordinate()` may be awaited from anywhere, so the stored request is guarded by a lock
/// rather than by an actor. The conformance is stated explicitly rather than designed around.
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
    /// Asks for when-in-use authorisation first when it has never been asked. The system sheet is
    /// modal and the answer arrives on the delegate, so the request is parked until it does; a
    /// refusal ends it there rather than sending a location request that would quietly fail.
    func currentCoordinate() async throws -> Coordinate {
        try await withCheckedThrowingContinuation { continuation in
            begin(continuation)
        }
    }

    private func begin(_ continuation: CheckedContinuation<Coordinate, Error>) {
        lock.lock()
        guard pending == nil else {
            lock.unlock()
            // One fix at a time. The app asks once per search, so a second caller is a mistake
            // rather than a queue to serve.
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

    /// Resumes the waiting call, once and only once.
    ///
    /// Every ending runs through here: a fix, a failure, a refusal, the countdown running out.
    /// Whoever gets to the continuation first takes it, and everyone after that finds nil and
    /// returns, which is what makes a late delegate callback harmless instead of fatal.
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
    /// Fires when the diner answers the permission sheet, and once when the delegate is first set,
    /// which is why nothing happens unless somebody is actually waiting on a fix.
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

/// What can go wrong when the app tries to work out where the diner is.
///
/// Every message here is read by someone standing on a footpath deciding where to eat, so each one
/// names what happened in their words and then what they can do about it. None of them is a dead
/// end: the search screen shows the message and the diner can change the setting, move, or simply
/// try again.
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
