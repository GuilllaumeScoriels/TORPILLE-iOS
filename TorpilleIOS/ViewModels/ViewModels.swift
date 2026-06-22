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
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

private func debugErrorMessage(_ error: Error) -> String {
    let nsError = error as NSError
    var extraLines: [String] = []

    if let details = nsError.userInfo[FunctionsErrorDetailsKey] {
        extraLines.append("details = \(details)")
    } else if let details = nsError.userInfo["details"] {
        extraLines.append("details = \(details)")
    }

    if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] {
        extraLines.append("failureReason = \(failureReason)")
    }

    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] {
        extraLines.append("underlying = \(underlyingError)")
    }

    let extraBlock = extraLines.isEmpty ? "" : "\n" + extraLines.joined(separator: "\n")
    return """
    \(nsError.domain) (\(nsError.code))
    \(nsError.localizedDescription)
    \(nsError.userInfo)
    \(extraBlock)
    """
}

private func isMissingProfileError(_ error: Error) -> Bool {
    guard let torpilleError = error as? TorpilleError else { return false }
    if case .missingData(let message) = torpilleError {
        return message.localizedCaseInsensitiveContains("profil introuvable")
    }
    return false
}

private func splitResponseTime(_ seconds: Int64) -> (hours: Int, minutes: Int) {
    let totalSeconds = max(seconds, 0)
    let hours = Int(totalSeconds / 3600)
    let minutes = Int((totalSeconds % 3600) / 60)
    return (hours, minutes)
}

func formatResponseTime(_ seconds: Int64) -> String {
    let components = splitResponseTime(seconds)
    switch (components.hours, components.minutes) {
    case (0, let minutes):
        return "\(minutes) min"
    case (let hours, 0):
        return hours == 1 ? "1 h" : "\(hours) h"
    case (let hours, let minutes):
        let hourText = hours == 1 ? "1 h" : "\(hours) h"
        return "\(hourText) \(minutes) min"
    }
}

enum AppRoute: Equatable {
    case splash
    case auth
    case profile
    case home
    case memories
    case createCommunity
    case join(String)
    case community(String)
    case communityInfo(String)
    case globalLeaderboard
    case notificationCenter
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
        guard !uid.isEmpty else {
            env.notificationCenterService.stop()
            route = .auth
            return
        }

        do {
            try await env.authRepository.reloadCurrentUser()
            try await env.authRepository.refreshIDToken()
        } catch {
            env.notificationCenterService.stop()
            route = .auth
            return
        }

        guard env.authRepository.isCurrentUserEmailVerified else {
            env.notificationCenterService.stop()
            do {
                try env.authRepository.signOut()
            } catch {}
            route = .auth
            return
        }

        env.notificationCenterService.start()

        do {
            let me = try await env.userRepository.getMeOrThrow()
            if let communityId = pendingJoinCommunityId, me.hasRequiredIdentity {
                route = .join(communityId)
            } else {
                route = me.hasRequiredIdentity ? .home : .profile
            }
        } catch {
            route = isMissingProfileError(error) ? .profile : .auth
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let communityId = extractCommunityId(from: url) else { return }

        pendingJoinCommunityId = communityId

        if env.authRepository.currentUID.isEmpty {
            env.notificationCenterService.stop()
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
            if !me.hasRequiredIdentity {
                route = .profile
            } else {
                route = .join(communityId)
            }
        } catch {
            route = isMissingProfileError(error) ? .profile : .auth
        }
    }

    func clearPendingJoin() {
        pendingJoinCommunityId = nil
    }


    func openNotificationCenter() {
        env.notificationCenterService.markAllAsRead()
        route = .notificationCenter
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
    private let languageService: AppLanguageService

    init(authRepository: AuthRepository, languageService: AppLanguageService) {
        self.authRepository = authRepository
        self.languageService = languageService
    }

    func signIn(onSuccess: @escaping () -> Void) {
        run(onSuccess: onSuccess) {
            try await self.authRepository.signIn(email: self.email, password: self.password)
            try await self.authRepository.reloadCurrentUser()
            try await self.authRepository.refreshIDToken()
            guard self.authRepository.isCurrentUserEmailVerified else {
                self.authRepository.setLanguageCode(self.languageService.firebaseAuthLanguageCode)
                try await self.authRepository.sendEmailVerification()
                let email = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
                try? self.authRepository.signOut()
                throw TorpilleError.missingData(
                    self.languageService.localizedEmailNotVerified(for: email)
                )
            }
        }
    }

    func signUp(onSuccess: @escaping () -> Void) {
        run(onSuccess: {}) {
            try await self.authRepository.signUp(email: self.email, password: self.password)
            self.authRepository.setLanguageCode(self.languageService.firebaseAuthLanguageCode)
            try await self.authRepository.sendEmailVerification()
            let email = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
            try? self.authRepository.signOut()
            self.infoMessage = self.languageService.localizedVerificationEmailSent(to: email)
        }
    }

    func resetPassword() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            error = languageService.localizedResetPasswordPrompt()
            return
        }

        error = nil
        infoMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                authRepository.setLanguageCode(languageService.firebaseAuthLanguageCode)
                try await authRepository.sendPasswordReset(email: cleanEmail)
                infoMessage = languageService.localizedResetPasswordInfo(for: cleanEmail)
            } catch {
                self.error = debugErrorMessage(error)
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
    @Published var selectedProfileIcon = "🎯"
    @Published var acceptsTerms = false
    
    private let repo: UserRepository
    private let authRepository: AuthRepository

    var email: String {
        authRepository.currentEmail
    }

    init(repo: UserRepository, authRepository: AuthRepository) {
        self.repo = repo
        self.authRepository = authRepository
    }

    var canSubmitProfile: Bool {
        !pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (selectedPhotoData != nil || !selectedProfileIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && acceptsTerms
    }

    func save(onDone: @escaping () -> Void) {
        error = nil
        guard canSubmitProfile else {
            error = "Complète ton pseudo, choisis un avatar et accepte les règles pour continuer."
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await repo.updateProfile(pseudo: pseudo, imageData: selectedPhotoData, profileIcon: selectedPhotoData == nil ? selectedProfileIcon : nil)
                let me = try await repo.getMeOrThrow()
                guard me.hasRequiredIdentity else {
                    throw TorpilleError.missingData("Le profil a été enregistré mais reste incomplet.")
                }
                onDone()
            } catch {
                self.error = debugErrorMessage(error)
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
    @Published var isDeletingAccount = false
    @Published var blockedUsers: [BlockedUser] = []
    @Published var friends: [PublicFriend] = []
    @Published var friendSearchResults: [UserProfile] = []
    @Published var isSearchingFriends = false

    private let authRepository: AuthRepository
    private let userRepository: UserRepository
    private let communityRepository: CommunityRepository
    private let languageService: AppLanguageService
    private var meRegistration: ListenerRegistration?
    private var communitiesRegistration: ListenerRegistration?
    private var blockedUsersRegistration: ListenerRegistration?
    private var friendsRegistration: ListenerRegistration?

    init(authRepository: AuthRepository, userRepository: UserRepository, communityRepository: CommunityRepository, languageService: AppLanguageService) {
        self.authRepository = authRepository
        self.userRepository = userRepository
        self.communityRepository = communityRepository
        self.languageService = languageService
    }

    var email: String {
        authRepository.currentEmail
    }

    var pinnedCommunityIds: [String] {
        Array((me?.pinnedCommunityIds ?? []).prefix(3))
    }

    var pinnedCommunities: [Community] {
        HomeCommunityPresentation.pinnedCommunities(from: communities, pinnedCommunityIds: pinnedCommunityIds)
    }

    var latestCommunity: Community? {
        communities.first
    }

    var homeCommunities: [Community] {
        HomeCommunityPresentation.homeCommunities(
            from: communities,
            pinnedCommunityIds: pinnedCommunityIds
        )
    }

    var orderedCommunities: [Community] {
        HomeCommunityPresentation.orderedCommunities(
            from: communities,
            pinnedCommunityIds: pinnedCommunityIds
        )
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
        blockedUsersRegistration = communityRepository.observeBlockedUsers { [weak self] values in
            DispatchQueue.main.async { self?.blockedUsers = values }
        }
        friendsRegistration = userRepository.observeFriends { [weak self] values in
            DispatchQueue.main.async { self?.friends = values }
        }

        Task {
            do {
                let communityIds = try await communityRepository.myCommunityIds()
                if communityIds.isEmpty {
                    try await communityRepository.syncMyTotalXP()
                } else {
                    for communityId in communityIds {
                        try await communityRepository.syncXPState(communityId: communityId)
                    }
                }
            } catch {
                print("⚠️ HomeViewModel.start non-blocking sync error:", debugErrorMessage(error))
            }
        }
    }

    func saveProfile(pseudo: String, imageData: Data?, profileIcon: String?) async -> Bool {
        error = nil
        infoMessage = nil
        do {
            try await userRepository.updateProfile(pseudo: pseudo, imageData: imageData, profileIcon: profileIcon)
            infoMessage = "Profil mis à jour."
            return true
        } catch {
            self.error = debugErrorMessage(error)
            return false
        }
    }

    func savePublicSettings(languageCode: String?, isLanguagePublic: Bool, isLeaderboardPublic: Bool) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await userRepository.updatePublicProfileSettings(
                    languageCode: languageCode,
                    isLanguagePublic: isLanguagePublic,
                    isLeaderboardPublic: isLeaderboardPublic
                )
                infoMessage = "Préférences publiques enregistrées."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func searchFriends(query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else {
            friendSearchResults = []
            return
        }
        isSearchingFriends = true
        Task {
            defer { isSearchingFriends = false }
            do {
                friendSearchResults = try await userRepository.searchUsersByPseudo(clean)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sendFriendRequest(to profile: UserProfile) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await userRepository.sendFriendRequest(to: profile)
                infoMessage = "Demande d'ami envoyée à @\(profile.pseudo)."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func resetPassword() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else {
            error = languageService.localizedResetPasswordPrompt()
            return
        }

        error = nil
        infoMessage = nil
        Task {
            do {
                authRepository.setLanguageCode(languageService.firebaseAuthLanguageCode)
                try await authRepository.sendPasswordReset(email: cleanEmail)
                infoMessage = languageService.localizedResetPasswordInfo(for: cleanEmail)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func signOut(onDone: @escaping () -> Void) {
        do {
            try authRepository.signOut()
            onDone()
        } catch {
            self.error = debugErrorMessage(error)
        }
    }

    func deleteAccount(onDone: @escaping () -> Void) {
        guard !isDeletingAccount else { return }

        error = nil
        infoMessage = nil
        isDeletingAccount = true

        Task {
            defer { isDeletingAccount = false }

            do {
                try await authRepository.reloadCurrentUser()
                try await authRepository.refreshIDToken()
                try await userRepository.deleteCurrentAccountServerSide()
                try authRepository.signOut()
                onDone()
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func unblockUser(_ blockedUser: BlockedUser) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await communityRepository.unblockUser(blockedUser.id)
                infoMessage = "@\(blockedUser.pseudo) a été débloqué."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func togglePinnedCommunity(_ community: Community) {
        error = nil
        infoMessage = nil

        let communityId = community.stableId
        let currentlyPinned = pinnedCommunityIds

        if currentlyPinned.contains(communityId) {
            let updatedIds = currentlyPinned.filter { $0 != communityId }
            Task {
                do {
                    try await userRepository.updatePinnedCommunities(updatedIds)
                    infoMessage = "Communauté retirée de l’accueil."
                } catch {
                    self.error = debugErrorMessage(error)
                }
            }
            return
        }

        guard currentlyPinned.count < 3 else {
            error = "Tu peux épingler jusqu’à 3 communautés."
            return
        }

        Task {
            do {
                try await userRepository.updatePinnedCommunities(currentlyPinned + [communityId])
                infoMessage = "Communauté épinglée dans l’accueil."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func isPinned(_ community: Community) -> Bool {
        pinnedCommunityIds.contains(community.stableId)
    }

    deinit {
        meRegistration?.remove()
        communitiesRegistration?.remove()
        blockedUsersRegistration?.remove()
        friendsRegistration?.remove()
    }
}

enum HomeCommunityPresentation {
    static func pinnedCommunities(from communities: [Community], pinnedCommunityIds: [String]) -> [Community] {
        let communitiesById = Dictionary(uniqueKeysWithValues: communities.map { ($0.stableId, $0) })
        return Array(pinnedCommunityIds.prefix(3)).compactMap { communitiesById[$0] }
    }

    static func homeCommunities(from communities: [Community], pinnedCommunityIds: [String]) -> [Community] {
        let pinned = pinnedCommunities(from: communities, pinnedCommunityIds: pinnedCommunityIds)
        if pinned.isEmpty {
            return communities.first.map { [$0] } ?? []
        }
        return pinned
    }

    static func orderedCommunities(from communities: [Community], pinnedCommunityIds: [String]) -> [Community] {
        let pinned = pinnedCommunities(from: communities, pinnedCommunityIds: pinnedCommunityIds)
        let pinnedIds = Set(pinned.map(\.stableId))
        let others = communities.filter { pinnedIds.contains($0.stableId) == false }
        return pinned + others
    }
}

enum LeaderboardXP {
    static func displayedXP(for player: UserProfile, selectedCommunityIds: Set<String>) -> Int64 {
        guard !selectedCommunityIds.isEmpty else { return player.effectiveTotalXP }
        return selectedCommunityIds.reduce(into: Int64(0)) { partial, communityId in
            partial += player.communityXP[communityId] ?? 0
        }
    }
}

@MainActor
final class GlobalLeaderboardViewModel: ObservableObject {
    @Published var players: [UserProfile] = []
    @Published var availableCommunities: [Community] = []
    @Published var selectedCommunityIds: Set<String> = []
    @Published var currentUserId: String?

    private let repo: UserRepository
    private let authRepository: AuthRepository
    private let communityRepository: CommunityRepository
    private var leaderboardRegistration: ListenerRegistration?
    private var communitiesRegistration: ListenerRegistration?
    private var allPlayers: [UserProfile] = []

    init(repo: UserRepository, authRepository: AuthRepository, communityRepository: CommunityRepository) {
        self.repo = repo
        self.authRepository = authRepository
        self.communityRepository = communityRepository
        self.currentUserId = authRepository.currentUID
    }

    var hasActiveCommunityFilter: Bool {
        !selectedCommunityIds.isEmpty
    }

    var filterDescription: String {
        guard hasActiveCommunityFilter else {
            return "Tous les utilisateurs de l'app"
        }

        let names = availableCommunities
            .filter { selectedCommunityIds.contains($0.stableId) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !names.isEmpty else {
            return "Communautés sélectionnées"
        }

        return names.joined(separator: ", ")
    }

    func start() {
        leaderboardRegistration?.remove()
        communitiesRegistration?.remove()

        currentUserId = authRepository.currentUID

        leaderboardRegistration = repo.observeGlobalLeaderboard { [weak self] values in
            DispatchQueue.main.async {
                self?.allPlayers = values
                self?.refreshPlayers()
            }
        }

        communitiesRegistration = communityRepository.observeCommunitiesForMe { [weak self] values in
            DispatchQueue.main.async {
                guard let self else { return }
                self.availableCommunities = values
                let validIds = Set(values.map(\.stableId))
                self.selectedCommunityIds = self.selectedCommunityIds.intersection(validIds)
                self.refreshPlayers()
            }
        }

        Task {
            do {
                let communityIds = try await communityRepository.myCommunityIds()
                if communityIds.isEmpty {
                    try await communityRepository.syncMyTotalXP()
                } else {
                    for communityId in communityIds {
                        try await communityRepository.syncXPState(communityId: communityId)
                    }
                }
            } catch {
                print(debugErrorMessage(error))
            }
        }
    }

    func toggleCommunity(_ communityId: String) {
        if selectedCommunityIds.contains(communityId) {
            selectedCommunityIds.remove(communityId)
        } else {
            selectedCommunityIds.insert(communityId)
        }
        refreshPlayers()
    }

    func clearCommunityFilters() {
        selectedCommunityIds.removeAll()
        refreshPlayers()
    }

    private func refreshPlayers() {
        guard hasActiveCommunityFilter else {
            players = allPlayers.sorted { lhs, rhs in
                if lhs.effectiveTotalXP != rhs.effectiveTotalXP {
                    return lhs.effectiveTotalXP > rhs.effectiveTotalXP
                }
                return lhs.pseudo.localizedCaseInsensitiveCompare(rhs.pseudo) == .orderedAscending
            }
            return
        }

        players = allPlayers
            .filter { profile in
                !selectedCommunityIds.isDisjoint(with: Set(profile.communityIds))
            }
            .sorted { lhs, rhs in
                let lhsXP = displayedXP(for: lhs)
                let rhsXP = displayedXP(for: rhs)
                if lhsXP != rhsXP {
                    return lhsXP > rhsXP
                }
                return lhs.pseudo.localizedCaseInsensitiveCompare(rhs.pseudo) == .orderedAscending
            }
    }

    func displayedXP(for player: UserProfile) -> Int64 {
        LeaderboardXP.displayedXP(for: player, selectedCommunityIds: selectedCommunityIds)
    }

    deinit {
        leaderboardRegistration?.remove()
        communitiesRegistration?.remove()
    }
}

@MainActor
final class CreateCommunityViewModel: ObservableObject {
    @Published var name = ""
    @Published var responseHours = 1
    @Published var responseMinutes = 0
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
                let response = Int64((responseHours * 3600) + (responseMinutes * 60))
                guard response > 0 else {
                    throw TorpilleError.invalidResponseTime
                }
                let me = try await userRepo.getMeOrThrow()
                let id = try await repo.createCommunity(name: name, isPublic: isPublic, responseTimeSeconds: response, me: me)
                self.error = nil
                onCreated(id)
            } catch {
                if isMissingProfileError(error) {
                    self.error = "Ton profil n'existe plus ou n'est pas encore terminé. Ouvre l'écran Profil, enregistre ton pseudo, puis réessaie."
                } else {
                    self.error = debugErrorMessage(error)
                }
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
            if isMissingProfileError(error) {
                self.error = "Ton profil n'existe plus ou n'est pas encore terminé. Ouvre l'écran Profil, enregistre ton pseudo, puis réessaie."
            } else {
                self.error = debugErrorMessage(error)
            }
        }
    }
}

@MainActor
final class CommunityInfoViewModel: ObservableObject {
    @Published var community: Community?
    @Published var members: [Member] = []
    @Published var savedMessageCount = 0
    @Published var responseHours = 1
    @Published var responseMinutes = 0
    @Published var isPublic = true
    @Published var rawAllowlist = ""
    @Published var error: String?
    @Published var infoMessage: String?

    private let repo: CommunityRepository
    private var communityRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var savedMessagesRegistration: ListenerRegistration?

    init(repo: CommunityRepository) {
        self.repo = repo
    }

    func start(communityId: String) {
        communityRegistration?.remove()
        membersRegistration?.remove()
        savedMessagesRegistration?.remove()

        communityRegistration = repo.observeCommunity(communityId) { [weak self] value in
            DispatchQueue.main.async {
                self?.community = value
                self?.isPublic = value?.isPublic ?? true
                let components = splitResponseTime(value?.responseTimeSeconds ?? 3600)
                self?.responseHours = components.hours
                self?.responseMinutes = components.minutes
            }
        }

        membersRegistration = repo.observeMembers(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.members = values
            }
        }

        savedMessagesRegistration = repo.observeSavedMessages(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.savedMessageCount = values.count
            }
        }
    }

    func saveSettings(communityId: String) {
        error = nil
        infoMessage = nil
        Task {
            do {
                let response = Int64((responseHours * 3600) + (responseMinutes * 60))
                guard response > 0 else {
                    throw TorpilleError.invalidResponseTime
                }
                try await repo.updateCommunitySettings(communityId: communityId, isPublic: isPublic, responseTimeSeconds: response)
                infoMessage = "Parametres enregistres."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    var canModerateMembers: Bool {
        guard let community else { return false }
        return community.adminUid == repo.currentUID && community.isPublic == false
    }

    func removeMember(communityId: String, member: Member) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.removeMember(communityId: communityId, memberUid: member.uid)
                infoMessage = "@\(member.displayName) a ete retire de la communaute."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func banMember(communityId: String, member: Member) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.banMember(communityId: communityId, member: member)
                infoMessage = "@\(member.displayName) a ete banni."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func hideContentFromMember(communityId: String, member: Member) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.hideMemberContent(communityId: communityId, member: member)
                infoMessage = "Les contenus de @\(member.displayName) sont masqués dans cette communauté."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func blockMember(_ member: Member) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.blockUser(member)
                infoMessage = "@\(member.displayName) a été bloqué."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    deinit {
        communityRegistration?.remove()
        membersRegistration?.remove()
        savedMessagesRegistration?.remove()
    }
}

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published var community: Community?
    @Published var messages: [Message] = []
    @Published var members: [Member] = []
    @Published var myMember: Member?
    @Published var me: UserProfile?
    @Published var unseenTorpilles: [Torpille] = []
    @Published var error: String?
    @Published var isSending = false
    @Published var infoMessage: String?
    @Published var firstUnreadMessageId: String?
    @Published var unreadReferenceDate: Date?
    @Published var publishNextTorpilleToReels = false
    @Published var publishResponseToReels = false

    private let communityRepo: CommunityRepository
    private let userRepo: UserRepository
    private var communityRegistration: ListenerRegistration?
    private var messagesRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var myMemberRegistration: ListenerRegistration?
    private var meRegistration: ListenerRegistration?
    private var torpillesRegistration: ListenerRegistration?
    private var lastMarkedMessageTimestamp: Timestamp?
    private var didCaptureInitialConnectionDate = false

    init(communityRepo: CommunityRepository, userRepo: UserRepository) {
        self.communityRepo = communityRepo
        self.userRepo = userRepo
    }

    func start(communityId: String) {
        communityRegistration?.remove()
        messagesRegistration?.remove()
        membersRegistration?.remove()
        myMemberRegistration?.remove()
        meRegistration?.remove()
        torpillesRegistration?.remove()
        didCaptureInitialConnectionDate = false
        unreadReferenceDate = nil

        meRegistration = userRepo.observeMe { [weak self] value in
            DispatchQueue.main.async { self?.me = value }
        }
        communityRegistration = communityRepo.observeCommunity(communityId) { [weak self] value in
            DispatchQueue.main.async { self?.community = value }
        }
        messagesRegistration = communityRepo.observeMessages(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.messages = values
                self?.refreshUnreadMessages()
            }
        }
        membersRegistration = communityRepo.observeMembers(communityId) { [weak self] values in
            DispatchQueue.main.async { self?.members = values }
        }
        myMemberRegistration = communityRepo.observeMyMember(communityId) { [weak self] value in
            DispatchQueue.main.async {
                if self?.didCaptureInitialConnectionDate == false {
                    self?.captureUnreadReferenceDate(from: value)
                }
                self?.myMember = value
                self?.refreshUnseenTorpilles()
                self?.refreshUnreadMessages()
            }
        }
        torpillesRegistration = communityRepo.observeRecentTorpilles(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.unseenTorpilles = values
                self?.refreshUnseenTorpilles()
            }
        }

        Task {
            do {
                let initialMember = try await communityRepo.fetchMyMember(communityId: communityId)
                await MainActor.run {
                    if self.didCaptureInitialConnectionDate == false {
                        self.captureUnreadReferenceDate(from: initialMember)
                    }
                }
                try await communityRepo.markCommunityOpened(communityId)
                try await communityRepo.syncXPState(communityId: communityId)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    private func captureUnreadReferenceDate(from member: Member?) {
        let lastSeen = member?.lastSeenMessageAt?.dateValue()
        let lastOpened = member?.lastOpenedAt?.dateValue()
        unreadReferenceDate = [lastSeen, lastOpened].compactMap { $0 }.max()
        didCaptureInitialConnectionDate = true
    }

    private func refreshUnseenTorpilles() {
        let myUID = me?.uid ?? communityRepo.currentUID
        let lastSeen = myMember?.lastSeenTorpilleAt?.dateValue() ?? .distantPast
        unseenTorpilles = unseenTorpilles
            .filter { $0.fromUid != myUID }
            .filter { ($0.createdAt?.dateValue() ?? .distantPast) > lastSeen }
            .sorted { ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast) }
    }

    private func refreshUnreadMessages() {
        let threshold = unreadReferenceDate ?? myMember?.lastSeenMessageAt?.dateValue() ?? .distantPast
        firstUnreadMessageId = messages.first(where: { ($0.createdAt?.dateValue() ?? .distantPast) > threshold })?.stableId
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
        infoMessage = nil
        Task {
            do {
                let senderPseudo = try await resolveSenderPseudo()
                try await communityRepo.sendText(communityId: communityId, senderPseudo: senderPseudo, text: trimmedText)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sendCapturedMedia(communityId: String, fileURL: URL) {
        error = nil
        infoMessage = nil
        isSending = true
        Task {
            defer { self.isSending = false }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                let ext = fileURL.pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
                    try await communityRepo.sendImageMessage(communityId: communityId, senderPseudo: senderPseudo, localFileURL: fileURL)
                } else {
                    try await communityRepo.sendCapturedVideoMessage(communityId: communityId, senderPseudo: senderPseudo, localFileURL: fileURL)
                }
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sendAudioMessage(communityId: String, fileURL: URL, durationSeconds: Double) {
        error = nil
        infoMessage = nil
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
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sendVideoTorpille(communityId: String, fileURL: URL, taggedMember: Member?, fallbackPseudoText: String, publishToReels: Bool, tagX: Double, tagY: Double) {
        let cleanFallbackPseudoText = fallbackPseudoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard taggedMember != nil || !cleanFallbackPseudoText.isEmpty else {
            error = "Indique un pseudo avant d'envoyer la torpille."
            return
        }

        error = nil
        infoMessage = nil
        isSending = true
        Task {
            defer { self.isSending = false }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                if myMember?.pendingTorpilleId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    guard let taggedMember else {
                        self.error = "Choisis un membre existant pour répondre à la torpille en attente."
                        return
                    }

                    try await communityRepo.respondWithVideo(
                        communityId: communityId,
                        senderPseudo: senderPseudo,
                        localFileURL: fileURL,
                        pendingTorpilleId: myMember?.pendingTorpilleId ?? "",
                        nextTaggedUid: taggedMember.uid,
                        nextTaggedPseudo: taggedMember.displayName,
                        publishToReels: publishToReels,
                        tagX: tagX,
                        tagY: tagY
                    )
                    self.publishNextTorpilleToReels = false
                    return
                }

                try await communityRepo.sendVideoTorpille(
                    communityId: communityId,
                    senderPseudo: senderPseudo,
                    localFileURL: fileURL,
                    taggedUid: taggedMember?.uid,
                    taggedPseudo: taggedMember?.displayName ?? cleanFallbackPseudoText,
                    publishToReels: publishToReels,
                    tagX: tagX,
                    tagY: tagY
                )
                self.publishNextTorpilleToReels = false
            } catch {
                let nsError = error as NSError
                self.error = """
                \(nsError.domain) (\(nsError.code))
                \(nsError.localizedDescription)
                \(nsError.userInfo)
                """
            }
        }
    }

    func respond(communityId: String, fileURL: URL, nextTaggedMember: Member, publishToReels: Bool, tagX: Double, tagY: Double) {
        guard let pendingTorpilleId = myMember?.pendingTorpilleId else { return }

        error = nil
        infoMessage = nil
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
                    publishToReels: publishToReels,
                    tagX: tagX,
                    tagY: tagY
                )
                self.publishResponseToReels = false
            } catch {
                let nsError = error as NSError
                self.error = """
                \(nsError.domain) (\(nsError.code))
                \(nsError.localizedDescription)
                \(nsError.userInfo)
                """
            }
        }
    }

    func markTorpillesSeen(communityId: String) {
        markTorpillesSeen(communityId: communityId, upTo: nil)
    }

    func markTorpillesSeen(communityId: String, upTo timestamp: Timestamp?) {
        Task {
            do {
                try await communityRepo.markTorpillesSeen(communityId: communityId, upTo: timestamp)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func markMessagesSeenIfNeeded(communityId: String) {
        guard let latestTimestamp = messages.last?.createdAt else { return }
        let alreadySeenAt = myMember?.lastSeenMessageAt?.dateValue() ?? .distantPast
        guard latestTimestamp.dateValue() > alreadySeenAt else { return }
        if let lastMarkedMessageTimestamp, lastMarkedMessageTimestamp.dateValue() >= latestTimestamp.dateValue() {
            return
        }

        lastMarkedMessageTimestamp = latestTimestamp
        Task {
            do {
                try await communityRepo.markMessagesSeen(communityId: communityId, upTo: latestTimestamp)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func saveMessage(communityId: String, message: Message) {
        guard !message.isSaved else {
            infoMessage = "Ce contenu est deja enregistre."
            return
        }
        guard let messageId = message.id, !messageId.isEmpty else {
            error = "Impossible d'enregistrer ce contenu."
            return
        }

        error = nil
        infoMessage = nil
        Task {
            do {
                let saverPseudo = try await resolveSenderPseudo()
                try await communityRepo.saveMessage(
                    communityId: communityId,
                    messageId: messageId,
                    savedByPseudo: saverPseudo
                )
                infoMessage = "Contenu enregistre dans la discussion."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func reportMessage(communityId: String, message: Message, reason: ReportReason, details: String) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await communityRepo.reportContent(
                    communityId: communityId,
                    contentId: message.stableId,
                    contentType: .message,
                    authorUid: message.senderUid,
                    authorPseudo: message.senderPseudo,
                    reason: reason,
                    details: details
                )
                infoMessage = "Signalement envoyé. Notre équipe vérifie la situation."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func hideContentFromSender(communityId: String, message: Message) {
        guard let member = members.first(where: { $0.uid == message.senderUid }) else { return }
        error = nil
        infoMessage = nil
        Task {
            do {
                try await communityRepo.hideMemberContent(communityId: communityId, member: member)
                infoMessage = "Les contenus de @\(member.displayName) sont masqués dans cette communauté."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func blockSender(message: Message) {
        guard let member = members.first(where: { $0.uid == message.senderUid }) else { return }
        error = nil
        infoMessage = nil
        Task {
            do {
                try await communityRepo.blockUser(member)
                infoMessage = "@\(member.displayName) a été bloqué."
            } catch {
                self.error = debugErrorMessage(error)
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
        if message.type == "image", let directURL = message.imageUrl, let url = URL(string: directURL) {
            return url
        }

        if let imagePath = message.imagePath {
            return try await communityRepo.getStoragePlaybackURL(path: imagePath, bucket: message.imageBucket)
        }
        if let audioPath = message.audioPath {
            return try await communityRepo.getStoragePlaybackURL(path: audioPath, bucket: message.audioBucket)
        }
        if let videoPath = message.videoPath {
            do {
                return try await communityRepo.getSignedPlaybackURL(videoPath: videoPath, videoBucket: message.videoBucket)
            } catch {
                return try await communityRepo.getStoragePlaybackURL(path: videoPath, bucket: message.videoBucket)
            }
        }
        throw TorpilleError.videoNotAvailable
    }

    func resolvePlaybackURL(for torpille: Torpille) async throws -> URL {
        if let directURL = torpille.videoUrl, let url = URL(string: directURL) {
            return url
        }
        if let videoPath = torpille.videoPath {
            do {
                return try await communityRepo.getSignedPlaybackURL(videoPath: videoPath, videoBucket: torpille.videoBucket)
            } catch {
                return try await communityRepo.getStoragePlaybackURL(path: videoPath, bucket: torpille.videoBucket)
            }
        }
        throw TorpilleError.videoNotAvailable
    }

    deinit {
        communityRegistration?.remove()
        messagesRegistration?.remove()
        membersRegistration?.remove()
        myMemberRegistration?.remove()
        meRegistration?.remove()
        torpillesRegistration?.remove()
    }
}

@MainActor
final class SavedCommunityMessagesViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var error: String?
    @Published var infoMessage: String?
    @Published var publishedTorpilleIds: Set<String> = []

    private let repo: CommunityRepository
    private var registration: ListenerRegistration?
    private var publishedReelsRegistration: ListenerRegistration?

    init(repo: CommunityRepository) {
        self.repo = repo
    }

    func start(communityId: String) {
        registration?.remove()
        publishedReelsRegistration?.remove()
        registration = repo.observeSavedMessages(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.messages = values
            }
        }
        publishedReelsRegistration = repo.observePublishedReelsForCommunity(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.publishedTorpilleIds = Set(values.map(\.torpilleId).filter { !$0.isEmpty })
            }
        }
    }

    func publishToMemories(communityId: String, message: Message) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.publishSavedTorpilleToReels(communityId: communityId, message: message)
                infoMessage = "La torpille a ete publiee dans Memories."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func removeFromMemories(communityId: String, message: Message) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.unpublishSavedTorpilleFromReels(communityId: communityId, message: message)
                infoMessage = "La torpille a ete retiree des Memories."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func canPublishToMemories(_ message: Message) -> Bool {
        message.type == "video"
            && message.senderUid == repo.currentUID
            && message.torpilleId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func isPublishedInMemories(_ message: Message) -> Bool {
        guard let torpilleId = message.torpilleId?.trimmingCharacters(in: .whitespacesAndNewlines), !torpilleId.isEmpty else {
            return false
        }
        return publishedTorpilleIds.contains(torpilleId)
    }

    func resolvePlaybackURL(for message: Message) async throws -> URL {
        if message.type == "audio", let directURL = message.audioUrl, let url = URL(string: directURL) {
            return url
        }
        if message.type == "video", let directURL = message.videoUrl, let url = URL(string: directURL) {
            return url
        }
        if message.type == "image", let directURL = message.imageUrl, let url = URL(string: directURL) {
            return url
        }
        if let imagePath = message.imagePath {
            return try await repo.getStoragePlaybackURL(path: imagePath, bucket: message.imageBucket)
        }
        if let audioPath = message.audioPath {
            return try await repo.getStoragePlaybackURL(path: audioPath, bucket: message.audioBucket)
        }
        if let videoPath = message.videoPath {
            do {
                return try await repo.getSignedPlaybackURL(videoPath: videoPath, videoBucket: message.videoBucket)
            } catch {
                return try await repo.getStoragePlaybackURL(path: videoPath, bucket: message.videoBucket)
            }
        }
        throw TorpilleError.videoNotAvailable
    }

    deinit {
        registration?.remove()
        publishedReelsRegistration?.remove()
    }
}

@MainActor
final class ReelsViewModel: ObservableObject {
    @Published var reels: [PublishedReel] = []
    @Published var error: String?
    @Published var infoMessage: String?
    @Published var selectedPublicProfile: UserProfile?
    @Published var isLoadingPublicProfile = false

    private let repo: CommunityRepository
    private var registration: ListenerRegistration?

    init(repo: CommunityRepository) {
        self.repo = repo
    }

    func start() {
        registration?.remove()
        registration = repo.observePublishedReels { [weak self] values in
            DispatchQueue.main.async {
                self?.reels = values
            }
        }
    }

    func removeFromMemories(_ reel: PublishedReel) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.unpublishReel(reel)
                infoMessage = "La torpille a ete retiree des Memories."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func canDelete(_ reel: PublishedReel) -> Bool {
        reel.authorUid == repo.currentUID
    }

    func resolvePlaybackURL(for reel: PublishedReel) async throws -> URL {
        if let directURL = reel.videoUrl, let url = URL(string: directURL) {
            return url
        }
        if let videoPath = reel.videoPath {
            do {
                return try await repo.getSignedPlaybackURL(videoPath: videoPath, videoBucket: reel.videoBucket)
            } catch {
                return try await repo.getStoragePlaybackURL(path: videoPath, bucket: reel.videoBucket)
            }
        }
        throw TorpilleError.videoNotAvailable
    }

    func openPublicProfile(for reel: PublishedReel) {
        error = nil
        isLoadingPublicProfile = true
        Task {
            defer { isLoadingPublicProfile = false }
            do {
                selectedPublicProfile = try await repo.publicUserProfile(uid: reel.authorUid)
            } catch {
                selectedPublicProfile = UserProfile(
                    uid: reel.authorUid,
                    email: "",
                    pseudo: reel.authorPseudo,
                    pseudoKey: "",
                    photoUrl: reel.authorPhotoUrl,
                    profileIcon: reel.authorProfileIcon,
                    communityIds: [],
                    pinnedCommunityIds: [],
                    communityXP: [:],
                    xpTotal: 0,
                    fcmToken: nil,
                    termsAcceptedAt: nil,
                    moderationRulesAcceptedAt: nil,
                    updatedAt: nil
                )
            }
        }
    }

    deinit {
        registration?.remove()
    }
}

@MainActor
final class MapViewModel: ObservableObject {
    @Published var communities: [Community] = []
    @Published var selectedCommunityId = ""
    @Published var members: [Member] = []
    @Published var showOnlyRecentlyConnected = false
    @Published var error: String?
    @Published var isSendingTorpille = false

    private let repo: CommunityRepository
    private let userRepository: UserRepository
    private let locationService: LocationService
    private var communitiesRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var sharedCommunityRegistrations: [String: ListenerRegistration] = [:]
    private var memberUIDsByCommunity: [String: Set<String>] = [:]
    private var membersByCommunity: [String: [Member]] = [:]

    init(repo: CommunityRepository, userRepository: UserRepository, locationService: LocationService) {
        self.repo = repo
        self.userRepository = userRepository
        self.locationService = locationService
    }

    var currentUserId: String {
        repo.currentUID
    }

    func start() {
        communitiesRegistration?.remove()
        removeSharedCommunityListeners()
        memberUIDsByCommunity = [:]
        membersByCommunity = [:]

        communitiesRegistration = repo.observeCommunitiesForMe { [weak self] values in
            DispatchQueue.main.async {
                guard let self else { return }
                self.communities = values
                self.updateSharedCommunityListeners(with: values)
                if values.contains(where: { $0.stableId == self.selectedCommunityId }) == false {
                    if let first = values.first {
                        self.selectedCommunityId = ""
                        self.members = self.allSharedMembers
                    } else {
                        self.selectedCommunityId = ""
                        self.members = []
                    }
                } else if self.selectedCommunityId.isEmpty {
                    self.members = self.allSharedMembers
                }
            }
        }
    }

    func selectCommunity(_ communityId: String) {
        selectedCommunityId = communityId
        if communityId.isEmpty {
            membersRegistration?.remove()
            members = allSharedMembers
        } else {
            listenMembers(for: communityId)
        }
    }

    func refreshLocation() {
        error = nil
        Task {
            do {
                let location = try await locationService.currentLocation()
                try await repo.updateMyLocation(in: communities.map { $0.stableId }, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sharedCommunities(with memberId: String) -> [Community] {
        communities.filter { community in
            let communityId = community.stableId
            return memberUIDsByCommunity[communityId]?.contains(memberId) == true
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func sendVideoTorpille(fileURL: URL, to member: MapMemberAnnotation, in communityId: String) {
        error = nil
        isSendingTorpille = true

        Task {
            defer { isSendingTorpille = false }

            do {
                let profile = try await userRepository.getMeOrThrow()
                let senderPseudo = profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanSenderPseudo = senderPseudo.isEmpty ? profile.uid : senderPseudo

                try await repo.sendVideoTorpille(
                    communityId: communityId,
                    senderPseudo: cleanSenderPseudo,
                    localFileURL: fileURL,
                    taggedUid: member.id,
                    taggedPseudo: member.pseudo,
                    publishToReels: false,
                    tagX: 0.5,
                    tagY: 0.2
                )
            } catch {
                self.error = debugErrorMessage(error)
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
        let sourceMembers = selectedCommunityId.isEmpty ? allSharedMembers : members
        guard showOnlyRecentlyConnected else {
            return sourceMembers
        }
        let limitDate = Date().addingTimeInterval(-1800)
        return sourceMembers.filter { member in
            guard let lastOpenedAt = member.lastOpenedAt?.dateValue() else { return false }
            return lastOpenedAt >= limitDate
        }
    }

    private var allSharedMembers: [Member] {
        let uniqueMembers = membersByCommunity.values
            .flatMap { $0 }
            .reduce(into: [String: Member]()) { partialResult, member in
                partialResult[member.uid] = member
            }
        return uniqueMembers.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
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

    private func updateSharedCommunityListeners(with communities: [Community]) {
        let desiredIds = Set(communities.map(\.stableId))
        let currentIds = Set(sharedCommunityRegistrations.keys)

        for communityId in currentIds.subtracting(desiredIds) {
            sharedCommunityRegistrations[communityId]?.remove()
            sharedCommunityRegistrations.removeValue(forKey: communityId)
            memberUIDsByCommunity.removeValue(forKey: communityId)
            membersByCommunity.removeValue(forKey: communityId)
        }

        for communityId in desiredIds.subtracting(currentIds) {
            sharedCommunityRegistrations[communityId] = repo.observeMembers(communityId) { [weak self] members in
                DispatchQueue.main.async {
                    self?.memberUIDsByCommunity[communityId] = Set(members.map(\.uid).filter { !$0.isEmpty })
                    self?.membersByCommunity[communityId] = members
                    if self?.selectedCommunityId.isEmpty == true {
                        self?.members = self?.allSharedMembers ?? []
                    }
                }
            }
        }
    }

    private func removeSharedCommunityListeners() {
        for registration in sharedCommunityRegistrations.values {
            registration.remove()
        }
        sharedCommunityRegistrations.removeAll()
        membersByCommunity.removeAll()
    }

    deinit {
        communitiesRegistration?.remove()
        membersRegistration?.remove()
        for registration in sharedCommunityRegistrations.values {
            registration.remove()
        }
    }
}


@MainActor
final class LaunchLocationSyncViewModel: ObservableObject {
    @Published var lastError: String?

    private let authRepository: AuthRepository
    private let repo: CommunityRepository
    private let locationService: LocationService
    private var hasSyncedInThisSession = false
    private var lastPresenceSyncAt: Date?

    init(authRepository: AuthRepository, repo: CommunityRepository, locationService: LocationService) {
        self.authRepository = authRepository
        self.repo = repo
        self.locationService = locationService
    }

    func syncOnAppOpenIfNeeded() async {
        guard !hasSyncedInThisSession else { return }
        guard !authRepository.currentUID.isEmpty else { return }
        hasSyncedInThisSession = true
        await syncPresenceAndLocationIfPossible()
    }

    func syncOnAppActive() async {
        guard !authRepository.currentUID.isEmpty else { return }
        if let lastPresenceSyncAt, Date().timeIntervalSince(lastPresenceSyncAt) < 60 {
            return
        }
        await syncPresenceAndLocationIfPossible()
    }

    private func syncPresenceAndLocationIfPossible() async {
        lastError = nil

        do {
            let communityIds = try await repo.myCommunityIds()
            guard !communityIds.isEmpty else { return }
            try await repo.markMeOpened(in: communityIds)
            lastPresenceSyncAt = Date()
        } catch {
            lastError = error.localizedDescription
            return
        }

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
            // The recently connected filter depends on app-open presence, not on location permission.
            // Keep this update best-effort so the launch signal still works without geolocation.
        }
    }
}
