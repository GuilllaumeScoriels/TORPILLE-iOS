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
import FirebaseStorage

private func debugDescribeStorageError(_ error: Error) -> String {
    let nsError = error as NSError
    return "domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)"
}

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

    func uploadCommunityImage(communityId: String, localFileURL: URL, filename: String) async throws -> UploadedImage {
        let path = "communities/\(communityId)/images/\(filename)"
        let bucket = try await uploadFile(localFileURL: localFileURL, storagePath: path)
        let url = try await resolveStoragePlaybackURL(path: path, bucket: bucket)
        return UploadedImage(bucket: bucket, storagePath: path, downloadURL: url.absoluteString)
    }

    func uploadProfileImage(uid: String, imageData: Data, filename: String) async throws -> UploadedImage {
        try await ensureAuthenticatedSession()
        print("✅ ensureAuthenticatedSession ok")

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

        let fileData: Data
        do {
            fileData = try Data(contentsOf: localFileURL, options: .mappedIfSafe)
            print("📁 fileData.count =", fileData.count)
        } catch {
            print("🔥 uploadFile read local file failed:", debugDescribeStorageError(error))
            throw TorpilleError.uploadFailed("Impossible de lire le média sélectionné avant l'envoi.")
        }

        guard !fileData.isEmpty else {
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
                _ = try await ref.putDataAsync(fileData, metadata: metadata)
                print("✅ putDataAsync ok on bucket =", bucket)
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
            let result = try await user.getIDTokenResult(forcingRefresh: true)
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


@MainActor
final class NotificationCenterService: NSObject, ObservableObject {
    @Published private(set) var items: [AppNotificationItem] = []
    @Published private(set) var communities: [Community] = []
    @Published private(set) var preferencesByCommunityId: [String: CommunityNotificationPreference] = [:]
    @Published var navigationTarget: String?

    private let communityRepository: CommunityRepository
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let notificationCenter = UNUserNotificationCenter.current()

    private var communitiesRegistration: ListenerRegistration?
    private var messageRegistrations: [String: ListenerRegistration] = [:]
    private var torpilleRegistrations: [String: ListenerRegistration] = [:]
    private var preferenceRegistrations: [String: ListenerRegistration] = [:]
    private var initialMessageIdsByCommunity: [String: Set<String>] = [:]
    private var initialTorpilleIdsByCommunity: [String: Set<String>] = [:]
    private var startedUID: String?

    private let itemsStorageKey = "torpille.localNotificationItems"
    private let maxStoredItems = 200

    init(communityRepository: CommunityRepository) {
        self.communityRepository = communityRepository
        super.init()
        loadPersistedItems()
        notificationCenter.delegate = self
    }

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
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
        }

        communitiesRegistration = communityRepository.observeCommunitiesForMe { [weak self] values in
            guard let self else { return }
            DispatchQueue.main.async {
                self.communities = values
                self.attachListeners(to: values)
            }
        }
    }

    func stop() {
        stopListenersOnly()
        startedUID = nil
        communities = []
        preferencesByCommunityId = [:]
        navigationTarget = nil
    }

    private func stopListenersOnly() {
        communitiesRegistration?.remove()
        communitiesRegistration = nil
        messageRegistrations.values.forEach { $0.remove() }
        torpilleRegistrations.values.forEach { $0.remove() }
        preferenceRegistrations.values.forEach { $0.remove() }
        messageRegistrations.removeAll()
        torpilleRegistrations.removeAll()
        preferenceRegistrations.removeAll()
        initialMessageIdsByCommunity.removeAll()
        initialTorpilleIdsByCommunity.removeAll()
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            print("🔔 notification authorization =", granted)
        } catch {
            print("🔔 notification authorization failed =", error)
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
                let knownIds = self.initialMessageIdsByCommunity[communityId] ?? []
                let currentIds = Set(values.map(\.stableId))
                if self.initialMessageIdsByCommunity[communityId] == nil {
                    self.initialMessageIdsByCommunity[communityId] = currentIds
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
        let isDirectMention = (message.taggedUid ?? "") == myUID
        if preference.mode == .mentionsOnly {
            guard isDirectMention else { return }
        } else if message.torpilleId != nil, isDirectMention {
            return
        }

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
        scheduleLocalNotification(for: item)
    }

    private func handleIncomingTorpille(_ torpille: Torpille, community: Community) {
        let myUID = auth.currentUser?.uid ?? ""
        guard !myUID.isEmpty, torpille.fromUid != myUID, torpille.toUid == myUID else { return }

        let preference = preference(for: community)
        guard preference.mode == .mentionsOnly || preference.mode == .all else { return }

        let sender = torpille.taggedPseudo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let sender, !sender.isEmpty {
            body = "Tu as été identifié·e dans \(community.name) : \(sender)."
        } else {
            body = "Tu as reçu une torpille dans \(community.name)."
        }

        let item = AppNotificationItem(
            id: "torpille_\(torpille.stableId)",
            communityId: community.stableId,
            communityName: community.name,
            title: "Nouvelle torpille",
            body: body,
            createdAt: torpille.createdAt?.dateValue() ?? Date(),
            isRead: false
        )
        insert(item)
        scheduleLocalNotification(for: item)
    }

    private func messageNotificationBody(for message: Message) -> String {
        let sender = message.senderPseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Quelqu’un" : message.senderPseudo
        switch message.type {
        case "text":
            let snippet = (message.text ?? "Nouveau message").trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(sender) : \(snippet.isEmpty ? "Nouveau message" : snippet)"
        case "audio":
            return "\(sender) a envoyé un vocal."
        case "image":
            return "\(sender) a envoyé une image."
        case "video":
            if let taggedPseudo = message.taggedPseudo?.trimmingCharacters(in: .whitespacesAndNewlines), !taggedPseudo.isEmpty {
                return "\(sender) a envoyé une vidéo pour \(taggedPseudo)."
            }
            return "\(sender) a envoyé une vidéo."
        default:
            return "\(sender) a envoyé un nouveau contenu."
        }
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
        if items.contains(where: { $0.id == item.id }) {
            return
        }
        items.insert(item, at: 0)
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
            applyBadgeCount()
        } catch {
            print("🔔 load items failed =", error)
        }
    }

    private func applyBadgeCount() {
        let count = unreadCount
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = count
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
            self?.navigationTarget = response.notification.request.content.userInfo["destination"] as? String
        }
        completionHandler()
    }
}
