/**
 Fichier : ViewModels.swift
 Rôle :
 - Contient les view models SwiftUI de l'application iOS.

 Ce que fait ce fichier :
 - Reprend la logique de navigation et d'état de l'application Android.
 - Expose les données nécessaires aux écrans : auth, profil, accueil,
   communautés, chat, carte et infos de communauté.
 - Encapsule les listeners Firestore et les actions utilisateur.

 Pourquoi c'est utile :
 - Les vues restent déclaratives.
 - La logique d'appel Firebase, de validation et de navigation reste testable.
 */

import Foundation
import SwiftUI
import FirebaseFirestore

enum AppRoute: Equatable {
    case splash
    case auth
    case profile
    case home
    case createCommunity
    case join(String)
    case community(String)
    case communityInfo(String)
}

@MainActor
final class AppRootViewModel: ObservableObject {
    @Published var route: AppRoute = .splash
    @Published var pendingJoinCommunityId: String?
    let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func bootstrap() async {
        let uid = env.authRepository.currentUID
        guard uid != nil else {
            route = .auth
            return
        }

        do {
            let me = try await env.userRepository.getMeOrThrow()
            let hasPseudo = !me.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let communityId = pendingJoinCommunityId, hasPseudo {
                route = .join(communityId)
            } else {
                route = hasPseudo ? .home : .profile
            }
        } catch {
            route = .profile
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let communityId = extractCommunityId(from: url) else { return }

        pendingJoinCommunityId = communityId

        if env.authRepository.currentUID == nil {
            route = .auth
            return
        }

        Task {
            await resumePendingJoinIfPossible()
        }
    }

    func resumePendingJoinIfPossible() async {
        guard let communityId = pendingJoinCommunityId else {
            route = .home
            return
        }

        do {
            let me = try await env.userRepository.getMeOrThrow()
            let pseudo = me.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)

            if pseudo.isEmpty {
                route = .profile
            } else {
                route = .join(communityId)
            }
        } catch {
            route = .profile
        }
    }

    func clearPendingJoin() {
        pendingJoinCommunityId = nil
    }

    private func extractCommunityId(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if url.scheme == "torpille" {
            if url.host == "join" || url.path == "/join" {
                return components?.queryItems?.first(where: { $0.name == "cid" })?.value
            }
        }

        if let host = url.host,
           host.contains("torpille-38783.web.app"),
           url.path == "/join" {
            return components?.queryItems?.first(where: { $0.name == "cid" })?.value
        }

        return nil
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var infoMessage: String?

    private let authRepository: AuthRepository

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
    }

    func signIn(onSuccess: @escaping () -> Void) {
        run(onSuccess: onSuccess) {
            try await self.authRepository.signIn(email: self.email, password: self.password)
        }
    }

    func signUp(onSuccess: @escaping () -> Void) {
        run(onSuccess: onSuccess) {
            try await self.authRepository.signUp(email: self.email, password: self.password)
        }
    }

    func resetPassword() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            error = "Renseigne ton email pour recevoir le lien de réinitialisation."
            return
        }

        error = nil
        infoMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await authRepository.sendPasswordReset(email: cleanEmail)
                infoMessage = "Un email de réinitialisation a été envoyé à \(cleanEmail)."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func run(onSuccess: @escaping () -> Void, _ block: @escaping () async throws -> Void) {
        error = nil
        infoMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await block()
                onSuccess()
            } catch {
                let nsError = error as NSError
                let details = String(describing: nsError.userInfo)
                if details.contains("API_KEY_SERVICE_BLOCKED") || details.contains("identitytoolkit") {
                    self.error = """
                    La connexion Firebase est bloquée côté console Google/Firebase.
                    La clé API iOS n'a pas accès à Identity Toolkit (Email/Mot de passe).
                    Ouvre Google Cloud Console > APIs & Services > Credentials > clé iOS du projet, puis autorise l'API identitytoolkit.googleapis.com.
                    """
                } else {
                    self.error = """
                    \(nsError.domain) (\(nsError.code))
                    \(nsError.localizedDescription)
                    """
                }
            }
        }
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var pseudo = ""
    @Published var isSaving = false
    @Published var error: String?
    @Published var selectedPhotoData: Data?
    @Published var selectedProfileIcon = "🍺"

    private let repo: UserRepository

    init(repo: UserRepository) {
        self.repo = repo
    }

    func save(onDone: @escaping () -> Void) {
        error = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await repo.updateProfile(pseudo: pseudo, imageData: selectedPhotoData, profileIcon: selectedProfileIcon)
                let me = try await repo.getMeOrThrow()
                let trimmedPseudo = me.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPseudo.isEmpty else {
                    throw TorpilleError.missingData("Le profil a été enregistré mais reste incomplet.")
                }
                onDone()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var me: UserProfile?
    @Published var communities: [Community] = []
    @Published var error: String?
    @Published var infoMessage: String?

    private let authRepository: AuthRepository
    private let userRepository: UserRepository
    private let communityRepository: CommunityRepository
    private var meRegistration: ListenerRegistration?
    private var communitiesRegistration: ListenerRegistration?

    init(authRepository: AuthRepository, userRepository: UserRepository, communityRepository: CommunityRepository) {
        self.authRepository = authRepository
        self.userRepository = userRepository
        self.communityRepository = communityRepository
    }

    var email: String {
        authRepository.currentEmail
    }

    func start() {
        meRegistration?.remove()
        communitiesRegistration?.remove()

        meRegistration = userRepository.observeMe { [weak self] profile in
            DispatchQueue.main.async { self?.me = profile }
        }
        communitiesRegistration = communityRepository.observeCommunitiesForMe { [weak self] values in
            DispatchQueue.main.async { self?.communities = values }
        }
    }

    func saveProfile(pseudo: String, imageData: Data?, profileIcon: String?) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await userRepository.updateProfile(pseudo: pseudo, imageData: imageData, profileIcon: profileIcon)
                infoMessage = "Profil mis à jour."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func resetPassword() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            error = "Aucun email associé au compte."
            return
        }

        error = nil
        infoMessage = nil
        Task {
            do {
                try await authRepository.sendPasswordReset(email: cleanEmail)
                infoMessage = "Un email de réinitialisation a été envoyé à \(cleanEmail)."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func signOut(onDone: @escaping () -> Void) {
        do {
            try authRepository.signOut()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }

    deinit {
        meRegistration?.remove()
        communitiesRegistration?.remove()
    }
}

@MainActor
final class CreateCommunityViewModel: ObservableObject {
    @Published var name = ""
    @Published var responseTime = "3600"
    @Published var isPublic = true
    @Published var isLoading = false
    @Published var error: String?

    private let repo: CommunityRepository
    private let userRepo: UserRepository

    init(repo: CommunityRepository, userRepo: UserRepository) {
        self.repo = repo
        self.userRepo = userRepo
    }

    func create(onCreated: @escaping (String) -> Void) {
        error = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                guard let response = Int64(responseTime), response > 0 else {
                    throw TorpilleError.invalidResponseTime
                }
                let me = try await userRepo.getMeOrThrow()
                let id = try await repo.createCommunity(name: name, isPublic: isPublic, responseTimeSeconds: response, me: me)
                onCreated(id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

@MainActor
final class JoinCommunityViewModel: ObservableObject {
    @Published var loading = false
    @Published var error: String?

    private let repo: CommunityRepository
    private let userRepo: UserRepository

    init(repo: CommunityRepository, userRepo: UserRepository) {
        self.repo = repo
        self.userRepo = userRepo
    }

    func join(_ communityId: String, onJoined: @escaping () -> Void) async {
        loading = true
        error = nil
        defer { loading = false }

        do {
            let me = try await userRepo.getMeOrThrow()
            try await repo.joinCommunity(communityId: communityId, me: me)
            onJoined()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class CommunityInfoViewModel: ObservableObject {
    @Published var community: Community?
    @Published var members: [Member] = []
    @Published var responseTime = "3600"
    @Published var isPublic = true
    @Published var rawAllowlist = ""
    @Published var error: String?

    private let repo: CommunityRepository
    private var communityRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?

    init(repo: CommunityRepository) {
        self.repo = repo
    }

    func start(communityId: String) {
        communityRegistration?.remove()
        membersRegistration?.remove()

        communityRegistration = repo.observeCommunity(communityId) { [weak self] value in
            DispatchQueue.main.async {
                self?.community = value
                self?.isPublic = value?.isPublic ?? true
                self?.responseTime = String(value?.responseTimeSeconds ?? 3600)
            }
        }

        membersRegistration = repo.observeMembers(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.members = values
            }
        }
    }

    func saveSettings(communityId: String) {
        error = nil
        Task {
            do {
                guard let response = Int64(responseTime), response > 0 else {
                    throw TorpilleError.invalidResponseTime
                }
                try await repo.updateCommunitySettings(communityId: communityId, isPublic: isPublic, responseTimeSeconds: response)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    deinit {
        communityRegistration?.remove()
        membersRegistration?.remove()
    }
}

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var members: [Member] = []
    @Published var myMember: Member?
    @Published var me: UserProfile?
    @Published var error: String?
    @Published var isSending = false

    private let communityRepo: CommunityRepository
    private let userRepo: UserRepository
    private var messagesRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var myMemberRegistration: ListenerRegistration?
    private var meRegistration: ListenerRegistration?

    init(communityRepo: CommunityRepository, userRepo: UserRepository) {
        self.communityRepo = communityRepo
        self.userRepo = userRepo
    }

    func start(communityId: String) {
        messagesRegistration?.remove()
        membersRegistration?.remove()
        myMemberRegistration?.remove()
        meRegistration?.remove()

        meRegistration = userRepo.observeMe { [weak self] value in
            DispatchQueue.main.async { self?.me = value }
        }
        messagesRegistration = communityRepo.observeMessages(communityId) { [weak self] values in
            DispatchQueue.main.async { self?.messages = values }
        }
        membersRegistration = communityRepo.observeMembers(communityId) { [weak self] values in
            DispatchQueue.main.async { self?.members = values }
        }
        myMemberRegistration = communityRepo.observeMyMember(communityId) { [weak self] value in
            DispatchQueue.main.async { self?.myMember = value }
        }
    }

    private func resolveSenderPseudo() async throws -> String {
        if let pseudo = me?.pseudo.trimmingCharacters(in: .whitespacesAndNewlines), !pseudo.isEmpty {
            return pseudo
        }

        let profile = try await userRepo.getMeOrThrow()
        let pseudo = profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pseudo.isEmpty else {
            throw TorpilleError.invalidPseudo
        }

        self.me = profile
        return pseudo
    }

    func sendText(communityId: String, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        error = nil
        Task {
            do {
                let senderPseudo = try await resolveSenderPseudo()
                try await communityRepo.sendText(communityId: communityId, senderPseudo: senderPseudo, text: trimmedText)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func sendAudioMessage(communityId: String, fileURL: URL, durationSeconds: Double) {
        error = nil
        isSending = true
        Task {
            defer { self.isSending = false }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                try await communityRepo.sendAudioMessage(
                    communityId: communityId,
                    senderPseudo: senderPseudo,
                    localFileURL: fileURL,
                    durationSeconds: durationSeconds
                )
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func sendVideoTorpille(communityId: String, fileURL: URL, taggedMember: Member, tagX: Double, tagY: Double) {
        error = nil
        isSending = true
        Task {
            defer { self.isSending = false }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                try await communityRepo.sendVideoTorpille(
                    communityId: communityId,
                    senderPseudo: senderPseudo,
                    localFileURL: fileURL,
                    taggedUid: taggedMember.uid,
                    taggedPseudo: taggedMember.displayName,
                    tagX: tagX,
                    tagY: tagY
                )
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func respond(communityId: String, fileURL: URL, nextTaggedMember: Member, tagX: Double, tagY: Double) {
        guard let pendingTorpilleId = myMember?.pendingTorpilleId else { return }

        error = nil
        isSending = true
        Task {
            defer { self.isSending = false }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                try await communityRepo.respondWithVideo(
                    communityId: communityId,
                    senderPseudo: senderPseudo,
                    localFileURL: fileURL,
                    pendingTorpilleId: pendingTorpilleId,
                    nextTaggedUid: nextTaggedMember.uid,
                    nextTaggedPseudo: nextTaggedMember.displayName,
                    tagX: tagX,
                    tagY: tagY
                )
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func resolvePlaybackURL(for message: Message) async throws -> URL {
        if message.type == "audio", let directURL = message.audioUrl, let url = URL(string: directURL) {
            return url
        }
        if message.type == "video", let directURL = message.videoUrl, let url = URL(string: directURL) {
            return url
        }

        if let audioPath = message.audioPath {
            return try await communityRepo.getSignedPlaybackURL(videoPath: audioPath, videoBucket: message.audioBucket)
        }
        if let videoPath = message.videoPath {
            return try await communityRepo.getSignedPlaybackURL(videoPath: videoPath, videoBucket: message.videoBucket)
        }
        throw TorpilleError.videoNotAvailable
    }

    deinit {
        messagesRegistration?.remove()
        membersRegistration?.remove()
        myMemberRegistration?.remove()
        meRegistration?.remove()
    }
}

@MainActor
final class MapViewModel: ObservableObject {
    @Published var communities: [Community] = []
    @Published var selectedCommunityId = ""
    @Published var members: [Member] = []
    @Published var showOnlyRecentlyConnected = false
    @Published var error: String?

    private let repo: CommunityRepository
    private let locationService: LocationService
    private var communitiesRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?

    init(repo: CommunityRepository, locationService: LocationService) {
        self.repo = repo
        self.locationService = locationService
    }

    func start() {
        communitiesRegistration?.remove()
        communitiesRegistration = repo.observeCommunitiesForMe { [weak self] values in
            DispatchQueue.main.async {
                self?.communities = values
                if self?.selectedCommunityId.isEmpty == true, let first = values.first {
                    self?.selectedCommunityId = first.stableId
                    self?.listenMembers(for: first.stableId)
                }
            }
        }
    }

    func selectCommunity(_ communityId: String) {
        selectedCommunityId = communityId
        listenMembers(for: communityId)
    }

    func refreshLocation() {
        error = nil
        Task {
            do {
                let location = try await locationService.currentLocation()
                try await repo.updateMyLocation(in: communities.map { $0.stableId }, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    var annotations: [MapMemberAnnotation] {
        filteredMembers.compactMap { member in
            guard let latitude = member.lastLatitude, let longitude = member.lastLongitude else { return nil }
            return MapMemberAnnotation(
                id: member.id,
                pseudo: member.displayName,
                latitude: latitude,
                longitude: longitude,
                subtitle: member.mapSubtitle,
                photoUrl: member.photoUrl,
                profileIcon: member.profileIcon,
                lastTorpilleTimeText: member.mapLastTorpilleTimeText
            )
        }
    }

    var visibleMembersCount: Int {
        filteredMembers.count
    }

    private var filteredMembers: [Member] {
        guard showOnlyRecentlyConnected else {
            return members
        }
        let limitDate = Date().addingTimeInterval(-1800)
        return members.filter { member in
            guard let lastLocationUpdatedAt = member.lastLocationUpdatedAt?.dateValue() else { return false }
            return lastLocationUpdatedAt >= limitDate
        }
    }

    private func listenMembers(for communityId: String) {
        membersRegistration?.remove()
        guard !communityId.isEmpty else {
            members = []
            return
        }
        membersRegistration = repo.observeMembersForMap(communityId) { [weak self] values in
            DispatchQueue.main.async { self?.members = values }
        }
    }

    deinit {
        communitiesRegistration?.remove()
        membersRegistration?.remove()
    }
}


@MainActor
final class LaunchLocationSyncViewModel: ObservableObject {
    @Published var lastError: String?

    private let repo: CommunityRepository
    private let locationService: LocationService
    private var hasSyncedInThisSession = false

    init(repo: CommunityRepository, locationService: LocationService) {
        self.repo = repo
        self.locationService = locationService
    }

    func syncOnAppOpenIfNeeded() async {
        guard !hasSyncedInThisSession else { return }
        hasSyncedInThisSession = true
        lastError = nil

        do {
            let communityIds = try await repo.myCommunityIds()
            guard !communityIds.isEmpty else { return }
            let location = try await locationService.currentLocation()
            try await repo.updateMyLocation(
                in: communityIds,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } catch {
            lastError = error.localizedDescription
        }
    }
}
