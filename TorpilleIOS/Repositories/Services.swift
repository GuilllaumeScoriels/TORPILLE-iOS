import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import UserNotifications
@preconcurrency import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import FirebaseFirestore
import FirebaseMessaging
import FirebaseStorage
import ImageIO

extension Notification.Name {
    static let torpilleDidReceiveFCMToken = Notification.Name("torpilleDidReceiveFCMToken")
}

enum MediaAudioSession {
    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        // A2DP is already supported by the playback category. Passing the
        // allowBluetoothA2DP option here can make AVAudioSession reject the
        // category/mode combination with OSStatus -50 on physical devices,
        // especially just after a playAndRecord voice-recording session.
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }
}

private func debugDescribeStorageError(_ error: Error) -> String {
    let nsError = error as NSError
    return "domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)"
}

@MainActor
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
        if authorizationContinuation != nil {
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
        if locationContinuation != nil {
            throw TorpilleError.locationUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
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

    func discardRecording() {
        let fileURL = recordedFileURL ?? recorder?.url
        clear()
        guard let fileURL else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch where (error as NSError).code == NSFileNoSuchFileError {
            // The temporary recording was already removed.
        } catch {
            print("⚠️ Unable to delete discarded voice recording:", error.localizedDescription)
        }
    }
}

final class VideoTransferService {
    private let configuredBucket: String
    private let candidateBuckets: [String]
    private let functions = Functions.functions(region: "europe-west1")

    init() {
        let rawBucket = Self.readConfiguredBucket()
        configuredBucket = Self.normalizedBucketName(from: rawBucket)
        candidateBuckets = configuredBucket.isEmpty ? [] : [configuredBucket]
    }

    func uploadCommunityVideo(communityId: String, localFileURL: URL, filename: String) async throws -> UploadedVideo {
        let preparedURL = try await prepareVideoForUpload(from: localFileURL)
        defer { try? FileManager.default.removeItem(at: preparedURL) }
        let optimizedFilename = (filename as NSString).deletingPathExtension + "." + preparedURL.pathExtension
        let path = "communities/\(communityId)/videos/\(optimizedFilename)"
        let bucket = try await uploadFile(localFileURL: preparedURL, storagePath: path)
        let url = try await resolveStoragePlaybackURL(path: path, bucket: bucket)
        return UploadedVideo(bucket: bucket, storagePath: path, downloadURL: url.absoluteString)
    }

    func uploadCommunityAudio(communityId: String, localFileURL: URL, filename: String, durationSeconds: Double) async throws -> UploadedAudio {
        let path = "communities/\(communityId)/audios/\(filename)"
        let bucket = try await uploadFile(localFileURL: localFileURL, storagePath: path)
        let url = try await resolveStoragePlaybackURL(path: path, bucket: bucket)
        return UploadedAudio(bucket: bucket, storagePath: path, downloadURL: url.absoluteString, durationSeconds: durationSeconds)
    }

    func uploadCommunityImage(communityId: String, localFileURL: URL, filename: String) async throws -> UploadedImage {
        let preparedURL = try prepareImageForUpload(from: localFileURL)
        defer { try? FileManager.default.removeItem(at: preparedURL) }
        let optimizedFilename = (filename as NSString).deletingPathExtension + ".jpg"
        let path = "communities/\(communityId)/images/\(optimizedFilename)"
        let bucket = try await uploadFile(localFileURL: preparedURL, storagePath: path)
        let url = try await resolveStoragePlaybackURL(path: path, bucket: bucket)
        return UploadedImage(bucket: bucket, storagePath: path, downloadURL: url.absoluteString)
    }

    func uploadProfileImage(uid: String, imageData: Data) async throws -> UploadedImage {
        try await ensureAuthenticatedSession()
        print("✅ ensureAuthenticatedSession ok")

        // One stable object per account prevents profile-picture versions from
        // accumulating every time the user updates their profile.
        let path = "users/\(uid)/profile/avatar.jpg"
        var lastError: Error?
        var attemptedBuckets: [String] = []

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public,max-age=3600"

        for bucket in candidateBuckets {
            attemptedBuckets.append(bucket)
            var uploadCompleted = false
            do {
                let storage = Self.storage(for: bucket)
                let ref = storage.reference(withPath: path)
                _ = try await ref.putDataAsync(imageData, metadata: metadata)
                uploadCompleted = true
                let downloadURL = try await ref.downloadURL()
                return UploadedImage(bucket: bucket, storagePath: path, downloadURL: downloadURL.absoluteString)
            } catch {
                lastError = error
                // Once the bytes were written, never retry in another bucket:
                // doing so would create a second unreferenced profile image.
                if uploadCompleted { break }
            }
        }

        throw mapStorageUploadError(lastError ?? TorpilleError.uploadFailed("Échec d'envoi image Firebase Storage."), buckets: attemptedBuckets)
    }

    func resolvePlaybackURL(videoPath: String, videoBucket: String?) async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw TorpilleError.notAuthenticated
        }

        _ = try await user.getIDTokenResult(forcingRefresh: false)

        var payload: [String: Any] = [
            "path": videoPath,
            "expiresIn": 3600
        ]
        if let videoBucket, !videoBucket.isEmpty {
            payload["bucket"] = videoBucket
        }

        do {
            let result = try await functions.httpsCallable("videoSignedUrl").call(payload)
            if let data = result.data as? [String: Any],
               let signedURLString = data["signedUrl"] as? String,
               let url = URL(string: signedURLString) {
                return url
            }
        } catch {
            print("⚠️ videoSignedUrl failed, fallback to Storage downloadURL:", error)
        }

        return try await resolveStoragePlaybackURL(path: videoPath, bucket: videoBucket)
    }

    func resolveStoragePlaybackURL(path: String, bucket: String?) async throws -> URL {
        guard Auth.auth().currentUser != nil else {
            throw TorpilleError.notAuthenticated
        }

        let storage: Storage
        if let bucket, !bucket.isEmpty {
            storage = Storage.storage(url: "gs://\(bucket)")
        } else {
            storage = Storage.storage()
        }

        let ref = storage.reference(withPath: path)
        return try await ref.downloadURL()
    }


    @discardableResult
    private func uploadFile(localFileURL: URL, storagePath: String) async throws -> String {
        let metadata = makeMetadata(for: localFileURL)

        print("📍 VideoTransferService.uploadFile")
        print("🪣 configuredBucket =", configuredBucket)
        print("🪣 candidateBuckets =", candidateBuckets)
        print("🪣 storagePath =", storagePath)
        print("📁 localFileURL =", localFileURL.path)
        print("📁 file exists =", FileManager.default.fileExists(atPath: localFileURL.path))
        print("📁 metadata.contentType =", metadata.contentType ?? "nil")

        let fileSize = try localFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("📁 file size =", fileSize)
        guard fileSize > 0 else {
            throw TorpilleError.uploadFailed("Le fichier sélectionné est vide ou inaccessible.")
        }

        try await ensureAuthenticatedSession()
        print("✅ ensureAuthenticatedSession ok")

        var lastError: Error?
        var attemptedBuckets: [String] = []

        for bucket in candidateBuckets {
            attemptedBuckets.append(bucket)
            do {
                let storage = Self.storage(for: bucket)
                print("🪣 bucket =", storage.reference().bucket)
                print("🪣 full path =", storagePath)
                let ref = storage.reference(withPath: storagePath)
                _ = try await ref.putFileAsync(from: localFileURL, metadata: metadata)
                print("✅ putFileAsync ok on bucket =", bucket)
                return bucket
            } catch {
                print("🔥 putDataAsync failed on bucket \(bucket):", debugDescribeStorageError(error))
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

        print("🔐 ensureAuthenticatedSession uid =", user.uid)
        print("🔐 ensureAuthenticatedSession email =", user.email ?? "nil")
        do {
            let result = try await user.getIDTokenResult(forcingRefresh: false)
            print("✅ ensureAuthenticatedSession token refresh ok")
            print("🔐 authTime =", result.authDate)
            print("🔐 expiration =", result.expirationDate)
        } catch {
            print("🔥 ensureAuthenticatedSession failed:", debugDescribeStorageError(error))
            throw error
        }
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
        metadata.cacheControl = "public,max-age=31536000,immutable"

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

    private func prepareVideoForUpload(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw TorpilleError.uploadFailed("Cette vidéo ne peut pas être préparée pour l’envoi.")
        }

        let outputType: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(outputType == .mp4 ? "mp4" : "mov")
        exporter.outputURL = destination
        exporter.outputFileType = outputType
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exporter.error ?? TorpilleError.uploadFailed("La préparation de la vidéo a échoué."))
                default:
                    continuation.resume(throwing: TorpilleError.uploadFailed("La préparation de la vidéo a été interrompue."))
                }
            }
        }

        let fileSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize > 0, fileSize < 200 * 1024 * 1024 else {
            try? FileManager.default.removeItem(at: destination)
            throw TorpilleError.uploadFailed("La vidéo est trop volumineuse. Choisis une vidéo plus courte.")
        }
        return destination
    }

    private func prepareImageForUpload(from sourceURL: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TorpilleError.uploadFailed("Cette image ne peut pas être préparée pour l’envoi.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TorpilleError.uploadFailed("La réduction de l’image a échoué.")
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw TorpilleError.uploadFailed("Impossible de créer l’image optimisée.")
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            try? FileManager.default.removeItem(at: destination)
            throw TorpilleError.uploadFailed("Impossible d’enregistrer l’image optimisée.")
        }
        return destination
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


@MainActor
final class NotificationCenterService: NSObject, ObservableObject {
    @Published private(set) var items: [AppNotificationItem] = []
    @Published private(set) var friendRequests: [FriendRequest] = []
    @Published private(set) var communityJoinRequests: [CommunityJoinRequest] = []
    @Published private(set) var communities: [Community] = []
    @Published private(set) var preferencesByCommunityId: [String: CommunityNotificationPreference] = [:]
    @Published var navigationTarget: String?
    @Published var navigationCommunityId: String?

    private let communityRepository: CommunityRepository
    private let userRepository: UserRepository
    private let languageService: AppLanguageService
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let notificationCenter = UNUserNotificationCenter.current()

    private var communitiesRegistration: ListenerRegistration?
    private var messageRegistrations: [String: ListenerRegistration] = [:]
    private var torpilleRegistrations: [String: ListenerRegistration] = [:]
    private var preferenceRegistrations: [String: ListenerRegistration] = [:]
    private var friendRequestsRegistration: ListenerRegistration?
    private var outgoingFriendRequestsRegistration: ListenerRegistration?
    private var friendRemovalsRegistration: ListenerRegistration?
    private var incomingCommunityJoinRequestsRegistration: ListenerRegistration?
    private var outgoingCommunityJoinRequestsRegistration: ListenerRegistration?
    private var initialMessageIdsByCommunity: [String: Set<String>] = [:]
    private var initialTorpilleIdsByCommunity: [String: Set<String>] = [:]
    private var latestMessagesByCommunity: [String: [Message]] = [:]
    private var initialIncomingFriendRequestIds: Set<String>?
    private var knownOutgoingFriendRequestStatuses: [String: String] = [:]
    private var knownOutgoingCommunityJoinRequestStatuses: [String: String] = [:]
    private var startedUID: String?

    private let itemsStorageKey = "torpille.localNotificationItems"
    private let maxStoredItems = 200
    private let activityRetentionInterval: TimeInterval = 14 * 24 * 60 * 60
    private var tokenObserver: NSObjectProtocol?

    init(communityRepository: CommunityRepository, userRepository: UserRepository, languageService: AppLanguageService) {
        self.communityRepository = communityRepository
        self.userRepository = userRepository
        self.languageService = languageService
        super.init()
        loadPersistedItems()
        notificationCenter.delegate = self
        tokenObserver = NotificationCenter.default.addObserver(
            forName: .torpilleDidReceiveFCMToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let token = notification.userInfo?["token"] as? String else { return }
            Task {
                try? await self.userRepository.registerFCMToken(token)
            }
        }
    }

    var unreadCount: Int {
        items.filter { !$0.isRead }.count + communityJoinRequests.count
    }

    func start() {
        let uid = auth.currentUser?.uid ?? ""
        guard !uid.isEmpty else {
            stop()
            return
        }

        guard startedUID != uid else { return }
        stopListenersOnly()
        startedUID = uid
        Task {
            await requestAuthorizationIfNeeded()
            await syncCurrentFCMTokenIfNeeded()
        }

        communitiesRegistration = communityRepository.observeCommunitiesForMe { [weak self] values in
            guard let self else { return }
            DispatchQueue.main.async {
                self.communities = values
                self.attachListeners(to: values)
            }
        }

        friendRequestsRegistration = db.collection("friendRequests")
            .whereField("toUid", isEqualTo: uid)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: FriendRequest.self) } ?? []
                DispatchQueue.main.async {
                    self?.handleIncomingFriendRequests(values)
                }
            }

        outgoingFriendRequestsRegistration = db.collection("friendRequests")
            .whereField("fromUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: FriendRequest.self) } ?? []
                DispatchQueue.main.async {
                    self?.handleOutgoingFriendRequests(values)
                }
            }

        friendRemovalsRegistration = db.collection("friendRemovals")
            .whereField("toUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: FriendRemoval.self) } ?? []
                DispatchQueue.main.async {
                    self?.handleFriendRemovals(values)
                }
            }

        incomingCommunityJoinRequestsRegistration = db.collection("communityJoinRequests")
            .whereField("adminUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: CommunityJoinRequest.self) } ?? []
                DispatchQueue.main.async { self?.handleIncomingCommunityJoinRequests(values) }
            }

        outgoingCommunityJoinRequestsRegistration = db.collection("communityJoinRequests")
            .whereField("requesterUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: CommunityJoinRequest.self) } ?? []
                DispatchQueue.main.async { self?.handleOutgoingCommunityJoinRequests(values) }
            }
    }

    func stop() {
        let currentStartedUID = startedUID
        let currentToken = Messaging.messaging().fcmToken
        if let currentStartedUID, let currentToken, !currentToken.isEmpty {
            Task {
                try? await userRepository.unregisterFCMToken(currentToken, for: currentStartedUID)
            }
        }
        stopListenersOnly()
        startedUID = nil
        communities = []
        preferencesByCommunityId = [:]
        navigationTarget = nil
        navigationCommunityId = nil
    }

    private func stopListenersOnly() {
        communitiesRegistration?.remove()
        communitiesRegistration = nil
        messageRegistrations.values.forEach { $0.remove() }
        torpilleRegistrations.values.forEach { $0.remove() }
        preferenceRegistrations.values.forEach { $0.remove() }
        friendRequestsRegistration?.remove()
        outgoingFriendRequestsRegistration?.remove()
        friendRemovalsRegistration?.remove()
        incomingCommunityJoinRequestsRegistration?.remove()
        outgoingCommunityJoinRequestsRegistration?.remove()
        messageRegistrations.removeAll()
        torpilleRegistrations.removeAll()
        preferenceRegistrations.removeAll()
        friendRequestsRegistration = nil
        outgoingFriendRequestsRegistration = nil
        friendRemovalsRegistration = nil
        incomingCommunityJoinRequestsRegistration = nil
        outgoingCommunityJoinRequestsRegistration = nil
        friendRequests = []
        communityJoinRequests = []
        initialMessageIdsByCommunity.removeAll()
        initialTorpilleIdsByCommunity.removeAll()
        latestMessagesByCommunity.removeAll()
        initialIncomingFriendRequestIds = nil
        knownOutgoingFriendRequestStatuses.removeAll()
        knownOutgoingCommunityJoinRequestStatuses.removeAll()
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            print("🔔 notification authorization =", granted)
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("🔔 notification authorization failed =", error)
        }
    }

    private func syncCurrentFCMTokenIfNeeded() async {
        guard auth.currentUser != nil else { return }
        if let existingToken = Messaging.messaging().fcmToken, !existingToken.isEmpty {
            try? await userRepository.registerFCMToken(existingToken)
            return
        }

        do {
            let token: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                Messaging.messaging().token { token, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: token ?? "")
                }
            }
            guard !token.isEmpty else { return }
            try? await userRepository.registerFCMToken(token)
        } catch {
            print("🔔 FCM token fetch failed =", error)
        }
    }

    private func attachListeners(to communities: [Community]) {
        let desiredIds = Set(communities.map(\.stableId))
        let currentMessageIds = Set(messageRegistrations.keys)
        let currentTorpilleIds = Set(torpilleRegistrations.keys)

        for communityId in currentMessageIds.subtracting(desiredIds) {
            messageRegistrations[communityId]?.remove()
            messageRegistrations.removeValue(forKey: communityId)
            initialMessageIdsByCommunity.removeValue(forKey: communityId)
            latestMessagesByCommunity.removeValue(forKey: communityId)
        }

        for communityId in currentTorpilleIds.subtracting(desiredIds) {
            torpilleRegistrations[communityId]?.remove()
            torpilleRegistrations.removeValue(forKey: communityId)
            initialTorpilleIdsByCommunity.removeValue(forKey: communityId)
        }

        for community in communities {
            let communityId = community.stableId
            if preferencesByCommunityId[communityId] == nil {
                preferencesByCommunityId[communityId] = CommunityNotificationPreference(
                    communityId: communityId,
                    communityName: community.name,
                    mode: .mentionsOnly,
                    updatedAt: nil
                )
            }
            if preferenceRegistrations[communityId] == nil {
                startPreferenceListenerIfNeeded(for: community)
            }
            if messageRegistrations[communityId] == nil {
                observeMessages(for: community)
            }
            if torpilleRegistrations[communityId] == nil {
                observeTorpilles(for: community)
            }
        }
    }

    private func observeMessages(for community: Community) {
        let communityId = community.stableId
        messageRegistrations[communityId] = communityRepository.observeMessages(communityId) { [weak self] values in
            guard let self else { return }
            DispatchQueue.main.async {
                self.latestMessagesByCommunity[communityId] = values
                let knownIds = self.initialMessageIdsByCommunity[communityId] ?? []
                let currentIds = Set(values.map(\.stableId))
                if self.initialMessageIdsByCommunity[communityId] == nil {
                    self.initialMessageIdsByCommunity[communityId] = currentIds
                    for message in values.sorted(by: {
                        ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast)
                    }) {
                        self.handleIncomingMessage(message, community: community)
                    }
                    return
                }

                let newMessages = values
                    .filter { !knownIds.contains($0.stableId) }
                    .sorted { ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast) }

                self.initialMessageIdsByCommunity[communityId] = currentIds

                for message in newMessages {
                    self.handleIncomingMessage(message, community: community)
                }
            }
        }
    }

    private func observeTorpilles(for community: Community) {
        let communityId = community.stableId
        torpilleRegistrations[communityId] = communityRepository.observeRecentTorpilles(communityId) { [weak self] values in
            guard let self else { return }
            DispatchQueue.main.async {
                let knownIds = self.initialTorpilleIdsByCommunity[communityId] ?? []
                let currentIds = Set(values.map(\.stableId))
                if self.initialTorpilleIdsByCommunity[communityId] == nil {
                    self.initialTorpilleIdsByCommunity[communityId] = currentIds

                    // A torpille can have arrived while the application was suspended or
                    // terminated. Replaying the initial (limited) snapshot makes sure the
                    // corresponding entry is restored in Activity when the app starts.
                    // insert(_:) deduplicates persisted entries by their stable identifier.
                    for torpille in values.sorted(by: {
                        ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast)
                    }) {
                        self.handleIncomingTorpille(torpille, community: community)
                    }
                    return
                }

                let newTorpilles = values
                    .filter { !knownIds.contains($0.stableId) }
                    .sorted { ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast) }

                self.initialTorpilleIdsByCommunity[communityId] = currentIds

                for torpille in newTorpilles {
                    self.handleIncomingTorpille(torpille, community: community)
                }
            }
        }
    }

    private func handleIncomingMessage(_ message: Message, community: Community) {
        let myUID = auth.currentUser?.uid ?? ""
        guard !myUID.isEmpty, message.senderUid != myUID else { return }

        let preference = preference(for: community)
        let isTorpilleMessage = message.torpilleId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let taggedUid = message.taggedUid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isTorpilleMessage, taggedUid == myUID { return }
        guard preference.mode == .all else { return }

        let item = AppNotificationItem(
            id: "message_\(message.stableId)",
            communityId: community.stableId,
            communityName: community.name,
            title: community.name,
            body: messageNotificationBody(for: message),
            createdAt: message.createdAt?.dateValue() ?? Date(),
            isRead: false
        )
        insert(item)
    }

    private func handleIncomingTorpille(_ torpille: Torpille, community: Community) {
        let myUID = auth.currentUser?.uid ?? ""
        guard !myUID.isEmpty, torpille.fromUid != myUID, torpille.toUid == myUID else { return }

        let preference = preference(for: community)
        guard shouldNotify(preference: preference, isExplicitlyIdentified: true) else { return }

        let senderPseudo = torpille.fromPseudo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = (senderPseudo?.isEmpty == false) ? senderPseudo! : ""
        let senderLabel = sender.isEmpty ? languageService.phrase("Un utilisateur") : "@\(sender)"
        let remainingTime = torpilleRemainingTimeText(torpille)
        let body = "\(senderLabel) \(languageService.phrase("t'a torpillé.")) \(languageService.phrase("Il te reste")) \(remainingTime) \(languageService.phrase("pour répondre."))"

        let item = AppNotificationItem(
            id: "torpille_\(torpille.stableId)",
            communityId: community.stableId,
            communityName: community.name,
            title: languageService.phrase("Torpille reçue"),
            body: body,
            createdAt: torpille.createdAt?.dateValue() ?? Date(),
            isRead: false,
            deepLink: "communityDiscussion"
        )
        insert(item)
    }

    private func torpilleRemainingTimeText(_ torpille: Torpille) -> String {
        guard let deadline = torpille.deadlineAt?.dateValue() else {
            return languageService.phrase("le délai prévu")
        }

        let remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h"
        }
        if minutes > 0 {
            return "\(minutes) min"
        }
        return languageService.phrase("moins d'une minute")
    }

    private func handleIncomingFriendRequests(_ values: [FriendRequest]) {
        friendRequests = values.sorted { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }

        let currentIds = Set(values.map(\.id))
        guard let knownIds = initialIncomingFriendRequestIds else {
            initialIncomingFriendRequestIds = currentIds
            return
        }

        let newRequests = values
            .filter { !knownIds.contains($0.id) }
            .sorted { ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast) }

        initialIncomingFriendRequestIds = currentIds

        for request in newRequests {
            let sender = request.fromPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
            let pseudo = sender.isEmpty ? languageService.phrase("Utilisateur") : "@\(sender)"
            insert(AppNotificationItem(
                id: "friend_request_\(request.id)",
                communityId: "",
                communityName: languageService.phrase("Activité"),
                title: languageService.phrase("Demande d'ami"),
                body: "\(pseudo) \(languageService.phrase("veut devenir ami avec toi."))",
                createdAt: request.createdAt?.dateValue() ?? Date(),
                isRead: false,
                deepLink: "notificationCenter"
            ))
        }
    }

    private func handleOutgoingFriendRequests(_ values: [FriendRequest]) {
        let previousStatuses = knownOutgoingFriendRequestStatuses
        let currentStatuses = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0.status) })
        guard !previousStatuses.isEmpty else {
            knownOutgoingFriendRequestStatuses = currentStatuses
            return
        }

        knownOutgoingFriendRequestStatuses = currentStatuses

        for request in values {
            let previousStatus = previousStatuses[request.id]
            guard previousStatus == FriendRequestStatus.pending.rawValue else { continue }
            guard request.status == FriendRequestStatus.accepted.rawValue || request.status == FriendRequestStatus.rejected.rawValue else { continue }

            let target = request.toPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
            let pseudo = target.isEmpty ? languageService.phrase("Utilisateur") : "@\(target)"
            let accepted = request.status == FriendRequestStatus.accepted.rawValue
            let body = accepted
                ? "\(pseudo) \(languageService.phrase("a accepté ta demande d'ami."))"
                : "\(pseudo) \(languageService.phrase("a refusé ta demande d'ami."))"

            insert(AppNotificationItem(
                id: "friend_request_\(request.status)_\(request.id)",
                communityId: "",
                communityName: languageService.phrase("Activité"),
                title: languageService.phrase("Demande d'ami"),
                body: body,
                createdAt: request.updatedAt?.dateValue() ?? Date(),
                isRead: false,
                deepLink: "notificationCenter"
            ))
        }
    }

    private func handleFriendRemovals(_ values: [FriendRemoval]) {
        for removal in values {
            let actor = removal.actorPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
            let pseudo = actor.isEmpty ? languageService.phrase("Un utilisateur") : "@\(actor)"
            insert(AppNotificationItem(
                id: "friend_removed_\(removal.id)",
                communityId: "",
                communityName: languageService.phrase("Activité"),
                title: languageService.phrase("Amitié terminée"),
                body: "\(pseudo) \(languageService.phrase("a mis fin à votre amitié."))",
                createdAt: removal.createdAt?.dateValue() ?? Date(),
                isRead: false,
                deepLink: "notificationCenter"
            ))
        }
    }

    private func handleIncomingCommunityJoinRequests(_ values: [CommunityJoinRequest]) {
        communityJoinRequests = values
            .filter { $0.status == CommunityJoinRequestStatus.pending.rawValue }
            .sorted { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }
        applyBadgeCount()
    }

    private func handleOutgoingCommunityJoinRequests(_ values: [CommunityJoinRequest]) {
        let previousStatuses = knownOutgoingCommunityJoinRequestStatuses
        knownOutgoingCommunityJoinRequestStatuses = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0.status) })

        for request in values {
            let isResolved = request.status == CommunityJoinRequestStatus.accepted.rawValue
                || request.status == CommunityJoinRequestStatus.rejected.rawValue
            guard isResolved else { continue }
            if !previousStatuses.isEmpty {
                guard previousStatuses[request.id] == CommunityJoinRequestStatus.pending.rawValue else { continue }
            }

            let accepted = request.status == CommunityJoinRequestStatus.accepted.rawValue
            insert(AppNotificationItem(
                id: "community_join_\(request.status)_\(request.id)",
                communityId: request.communityId,
                communityName: request.communityName,
                title: languageService.communityJoinDecisionTitle(accepted: accepted),
                body: languageService.communityJoinDecisionBody(communityName: request.communityName, accepted: accepted),
                createdAt: request.resolvedAt?.dateValue() ?? request.updatedAt?.dateValue() ?? Date(),
                isRead: false,
                deepLink: accepted ? "communityDiscussion" : "notificationCenter"
            ))
        }
    }

    private func shouldNotify(preference: CommunityNotificationPreference, isExplicitlyIdentified: Bool) -> Bool {
        switch preference.mode {
        case .all:
            return true
        case .mentionsOnly:
            return isExplicitlyIdentified
        }
    }

    private func messageNotificationBody(for message: Message) -> String {
        let sender = message.senderPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let taggedPseudo = message.taggedPseudo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: NotificationMessageKind
        switch message.type {
        case "text": kind = .text
        case "audio": kind = .audio
        case "image": kind = .image
        case "video": kind = .video
        default: kind = .other
        }

        return languageService.localizedNotificationBody(
            for: NotificationMessageDescriptor(
                sender: sender,
                type: kind,
                snippet: snippet,
                taggedPseudo: taggedPseudo
            )
        )
    }

    private func scheduleLocalNotification(for item: AppNotificationItem) {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = [
            "destination": item.deepLink,
            "communityId": item.communityId
        ]

        let request = UNNotificationRequest(
            identifier: item.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        notificationCenter.add(request)
    }

    private func insert(_ item: AppNotificationItem) {
        removeExpiredActivityItems()
        if items.contains(where: { $0.id == item.id }) {
            persistItems()
            applyBadgeCount()
            return
        }
        items.append(item)
        sortActivityItems()
        if items.count > maxStoredItems {
            items = Array(items.prefix(maxStoredItems))
        }
        persistItems()
        applyBadgeCount()
    }

    func markAllAsRead() {
        items = items.map {
            var updated = $0
            updated.isRead = true
            return updated
        }
        persistItems()
        applyBadgeCount()
    }

    func clearAllNotifications() {
        let notificationIds = items.map(\.id)
        items.removeAll()
        persistItems()
        applyBadgeCount()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIds)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: notificationIds)
    }

    func resetForSignedOutUser() {
        stop()
        clearAllNotifications()
        UserDefaults.standard.removeObject(forKey: itemsStorageKey)
    }

    func markAsRead(_ itemId: String) {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].isRead = true
        persistItems()
        applyBadgeCount()
    }

    func deleteNotification(_ itemId: String) {
        items.removeAll { $0.id == itemId }
        persistItems()
        applyBadgeCount()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [itemId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [itemId])
    }

    func acceptFriendRequest(_ request: FriendRequest) {
        Task {
            do {
                try await userRepository.acceptFriendRequest(request)
                friendRequests.removeAll { $0.id == request.id }
            } catch {
                print("⚠️ acceptFriendRequest failed:", error)
            }
        }
    }

    func rejectFriendRequest(_ request: FriendRequest) {
        Task {
            do {
                try await userRepository.rejectFriendRequest(request)
                friendRequests.removeAll { $0.id == request.id }
            } catch {
                print("⚠️ rejectFriendRequest failed:", error)
            }
        }
    }

    func resolveCommunityJoinRequest(_ request: CommunityJoinRequest, accept: Bool) {
        Task {
            do {
                try await communityRepository.resolveJoinRequest(request, accept: accept)
            } catch {
                print("⚠️ resolveCommunityJoinRequest failed:", error)
            }
        }
    }

    func updatePreference(for community: Community, mode: CommunityNotificationMode) {
        let uid = auth.currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }

        let preference = CommunityNotificationPreference(
            communityId: community.stableId,
            communityName: community.name,
            mode: mode,
            updatedAt: Timestamp(date: Date())
        )
        preferencesByCommunityId[community.stableId] = preference
        if mode == .all {
            for message in latestMessagesByCommunity[community.stableId] ?? [] {
                handleIncomingMessage(message, community: community)
            }
        }

        Task {
            do {
                try db.collection("users")
                    .document(uid)
                    .collection("notificationPreferences")
                    .document(community.stableId)
                    .setData(from: preference)
            } catch {
                print("🔔 save preference failed =", error)
            }
        }
    }

    func preference(for community: Community) -> CommunityNotificationPreference {
        if let value = preferencesByCommunityId[community.stableId] {
            return value
        }
        return CommunityNotificationPreference(
            communityId: community.stableId,
            communityName: community.name,
            mode: .mentionsOnly,
            updatedAt: nil
        )
    }

    private func startPreferenceListenerIfNeeded(for community: Community) {
        let uid = auth.currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }
        let ref = db.collection("users").document(uid).collection("notificationPreferences").document(community.stableId)
        preferenceRegistrations[community.stableId] = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if let snapshot, snapshot.exists, let value = try? snapshot.data(as: CommunityNotificationPreference.self) {
                    self.preferencesByCommunityId[community.stableId] = value
                    if value.mode == .all {
                        for message in self.latestMessagesByCommunity[community.stableId] ?? [] {
                            self.handleIncomingMessage(message, community: community)
                        }
                    }
                } else if self.preferencesByCommunityId[community.stableId] == nil {
                    self.preferencesByCommunityId[community.stableId] = CommunityNotificationPreference(
                        communityId: community.stableId,
                        communityName: community.name,
                        mode: .mentionsOnly,
                        updatedAt: nil
                    )
                }
            }
        }
    }

    private func persistItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: itemsStorageKey)
        } catch {
            print("🔔 persist items failed =", error)
        }
    }

    private func loadPersistedItems() {
        guard let data = UserDefaults.standard.data(forKey: itemsStorageKey) else { return }
        do {
            items = try JSONDecoder().decode([AppNotificationItem].self, from: data)
            removeExpiredActivityItems()
            sortActivityItems()
            persistItems()
            applyBadgeCount()
        } catch {
            print("🔔 load items failed =", error)
        }
    }

    private func sortActivityItems() {
        items.sort { lhs, rhs in
            let lhsIsTorpille = lhs.id.hasPrefix("torpille_")
            let rhsIsTorpille = rhs.id.hasPrefix("torpille_")
            if lhsIsTorpille != rhsIsTorpille {
                return lhsIsTorpille
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func removeExpiredActivityItems(referenceDate: Date = Date()) {
        let cutoffDate = referenceDate.addingTimeInterval(-activityRetentionInterval)
        let expiredIds = items
            .filter { $0.createdAt < cutoffDate }
            .map(\.id)
        guard !expiredIds.isEmpty else { return }

        items.removeAll { $0.createdAt < cutoffDate }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: expiredIds)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: expiredIds)
    }

    private func applyBadgeCount() {
        let count = unreadCount
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    deinit {
        if let tokenObserver {
            NotificationCenter.default.removeObserver(tokenObserver)
        }
    }
}

extension NotificationCenterService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in
            let userInfo = response.notification.request.content.userInfo
            self?.navigationCommunityId = userInfo["communityId"] as? String
            self?.navigationTarget = userInfo["destination"] as? String
        }
        completionHandler()
    }
}
