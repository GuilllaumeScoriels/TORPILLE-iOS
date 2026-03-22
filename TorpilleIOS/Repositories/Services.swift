import Foundation
import UniformTypeIdentifiers
import AVFoundation
@preconcurrency import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import FirebaseStorage

final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionIfNeeded() async throws {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            return
        }
        guard status == .notDetermined else {
            throw TorpilleError.locationUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocation {
        try await requestPermissionIfNeeded()

        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw TorpilleError.locationUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        case .denied, .restricted:
            authorizationContinuation?.resume(throwing: TorpilleError.locationUnavailable)
            authorizationContinuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}

@MainActor
final class AudioRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var recordedFileURL: URL?
    @Published private(set) var recordedDurationSeconds: Double = 0

    private var recorder: AVAudioRecorder?

    func startRecording() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        switch session.recordPermission {
        case .granted:
            break
        case .denied:
            throw TorpilleError.missingData("L'accès au microphone est refusé.")
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard granted else {
                throw TorpilleError.missingData("L'accès au microphone est nécessaire pour envoyer un vocal.")
            }
        @unknown default:
            throw TorpilleError.missingData("Impossible de vérifier l'autorisation du microphone.")
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: destination, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw TorpilleError.uploadFailed("Le démarrage de l'enregistrement vocal a échoué.")
        }

        self.recorder = recorder
        self.recordedFileURL = nil
        self.recordedDurationSeconds = 0
        self.isRecording = true
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw TorpilleError.missingData("Aucun enregistrement vocal en cours.")
        }

        recorder.stop()
        recordedDurationSeconds = recorder.currentTime
        recordedFileURL = recorder.url
        isRecording = false
        self.recorder = nil
        return recorder.url
    }

    func clear() {
        if let recorder, recorder.isRecording {
            recorder.stop()
        }
        recorder = nil
        isRecording = false
        recordedFileURL = nil
        recordedDurationSeconds = 0
    }
}

final class VideoTransferService {
    private let configuredBucket: String
    private let candidateBuckets: [String]
    private let functions = Functions.functions(region: "europe-west1")

    init() {
        let rawBucket = Self.readConfiguredBucket()
        configuredBucket = Self.normalizedBucketName(from: rawBucket)
        candidateBuckets = Self.makeCandidateBuckets(configuredBucket: configuredBucket)
    }

    func uploadCommunityVideo(communityId: String, localFileURL: URL, filename: String) async throws -> UploadedVideo {
        let path = "communities/\(communityId)/videos/\(filename)"
        let bucket = try await uploadFile(localFileURL: localFileURL, storagePath: path)
        return UploadedVideo(bucket: bucket, storagePath: path)
    }

    func uploadCommunityAudio(communityId: String, localFileURL: URL, filename: String, durationSeconds: Double) async throws -> UploadedAudio {
        let path = "communities/\(communityId)/audios/\(filename)"
        let bucket = try await uploadFile(localFileURL: localFileURL, storagePath: path)
        return UploadedAudio(bucket: bucket, storagePath: path, durationSeconds: durationSeconds)
    }

    func uploadProfileImage(uid: String, imageData: Data, filename: String) async throws -> UploadedImage {
        try await ensureAuthenticatedSession()

        let path = "users/\(uid)/profile/\(filename)"
        var lastError: Error?
        var attemptedBuckets: [String] = []

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public,max-age=3600"

        for bucket in candidateBuckets {
            attemptedBuckets.append(bucket)
            do {
                let storage = Self.storage(for: bucket)
                let ref = storage.reference(withPath: path)
                _ = try await ref.putDataAsync(imageData, metadata: metadata)
                let downloadURL = try await ref.downloadURL()
                return UploadedImage(bucket: bucket, storagePath: path, downloadURL: downloadURL.absoluteString)
            } catch {
                lastError = error
            }
        }

        throw mapStorageUploadError(lastError ?? TorpilleError.uploadFailed("Échec d'envoi image Firebase Storage."), buckets: attemptedBuckets)
    }

    func resolvePlaybackURL(videoPath: String, videoBucket: String?) async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw TorpilleError.notAuthenticated
        }

        _ = try await user.getIDTokenResult(forcingRefresh: true)

        var payload: [String: Any] = [
            "path": videoPath,
            "expiresIn": 3600
        ]
        if let videoBucket, !videoBucket.isEmpty {
            payload["bucket"] = videoBucket
        }

        let result = try await functions.httpsCallable("videoSignedUrl").call(payload)
        guard let data = result.data as? [String: Any],
              let signedURLString = data["signedUrl"] as? String,
              let url = URL(string: signedURLString) else {
            throw TorpilleError.videoNotAvailable
        }

        return url
    }


    @discardableResult
    private func uploadFile(localFileURL: URL, storagePath: String) async throws -> String {
        let metadata = makeMetadata(for: localFileURL)

        let fileData: Data
        do {
            fileData = try Data(contentsOf: localFileURL, options: .mappedIfSafe)
        } catch {
            throw TorpilleError.uploadFailed("Impossible de lire le média sélectionné avant l'envoi.")
        }

        guard !fileData.isEmpty else {
            throw TorpilleError.uploadFailed("Le fichier sélectionné est vide ou inaccessible.")
        }

        try await ensureAuthenticatedSession()

        var lastError: Error?
        var attemptedBuckets: [String] = []

        for bucket in candidateBuckets {
            attemptedBuckets.append(bucket)
            do {
                let storage = Self.storage(for: bucket)
                let ref = storage.reference(withPath: storagePath)
                _ = try await ref.putDataAsync(fileData, metadata: metadata)
                return bucket
            } catch {
                lastError = error
            }
        }

        throw mapStorageUploadError(lastError ?? TorpilleError.uploadFailed("Échec d'envoi Firebase Storage."), buckets: attemptedBuckets)
    }

    private static func readConfiguredBucket() -> String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let bucket = dict["STORAGE_BUCKET"] as? String,
              !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return bucket.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedBucketName(from rawBucket: String) -> String {
        let clean = rawBucket
            .replacingOccurrences(of: "gs://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !clean.isEmpty {
            return clean
        }

        if let app = FirebaseApp.app(),
           let fallbackBucket = app.options.storageBucket,
           !fallbackBucket.isEmpty {
            return normalizedBucketName(from: fallbackBucket)
        }

        if let projectID = FirebaseApp.app()?.options.projectID,
           !projectID.isEmpty {
            return "\(projectID).firebasestorage.app"
        }

        return ""
    }

    private static func makeCandidateBuckets(configuredBucket: String) -> [String] {
        var buckets: [String] = []

        func append(_ raw: String?) {
            guard let raw else { return }
            let normalized = normalizedBucketName(from: raw)
            guard !normalized.isEmpty, !buckets.contains(normalized) else { return }
            buckets.append(normalized)
        }

        append(configuredBucket)
        append(readConfiguredBucket())
        append(FirebaseApp.app()?.options.storageBucket)

        if buckets.isEmpty,
           let projectID = FirebaseApp.app()?.options.projectID,
           !projectID.isEmpty {
            append("\(projectID).firebasestorage.app")
        }

        return buckets
    }

    private func ensureAuthenticatedSession() async throws {
        guard let user = Auth.auth().currentUser else {
            throw TorpilleError.notAuthenticated
        }

        _ = try await user.getIDTokenResult(forcingRefresh: true)
    }

    private static func storage(for bucket: String) -> Storage {
        if let defaultBucket = FirebaseApp.app()?.options.storageBucket,
           normalizedBucketName(from: defaultBucket) == normalizedBucketName(from: bucket) {
            return Storage.storage()
        }
        return Storage.storage(url: "gs://\(bucket)")
    }

    private func makeMetadata(for localFileURL: URL) -> StorageMetadata {
        let metadata = StorageMetadata()
        metadata.cacheControl = "public,max-age=3600"

        let ext = localFileURL.pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext),
           let mime = utType.preferredMIMEType {
            metadata.contentType = mime
        } else if ext == "mov" {
            metadata.contentType = "video/quicktime"
        } else if ext == "mp4" {
            metadata.contentType = "video/mp4"
        } else if ext == "m4a" {
            metadata.contentType = "audio/mp4"
        } else {
            metadata.contentType = "application/octet-stream"
        }

        return metadata
    }

    private func mapStorageUploadError(_ error: Error, buckets: [String]) -> Error {
        let nsError = error as NSError
        let message = nsError.localizedDescription.lowercased()
        let triedBuckets = buckets.joined(separator: ", ")

        if nsError.domain == StorageErrorDomain || nsError.domain.contains("FIRStorageErrorDomain") {
            if nsError.code == StorageErrorCode.unauthenticated.rawValue || message.contains("unauthenticated") {
                return TorpilleError.uploadFailed("L'envoi a été refusé car la session Firebase n'est pas reconnue côté Storage.")
            }

            if nsError.code == StorageErrorCode.unauthorized.rawValue || message.contains("unauthorized") || message.contains("permission") {
                return TorpilleError.uploadFailed("L'envoi est refusé par les règles Firebase Storage ou par App Check.")
            }

            if nsError.code == StorageErrorCode.bucketNotFound.rawValue || (message.contains("bucket") && message.contains("not found")) {
                return TorpilleError.uploadFailed("Le bucket Firebase Storage est introuvable. Buckets testés : \(triedBuckets).")
            }

            if nsError.code == StorageErrorCode.retryLimitExceeded.rawValue {
                return TorpilleError.uploadFailed("Le transfert a dépassé le temps limite côté Firebase Storage.")
            }
        }

        return TorpilleError.uploadFailed("Échec de l'envoi. Buckets testés : \(triedBuckets). Erreur : \(nsError.domain) / \(nsError.code).")
    }
}
