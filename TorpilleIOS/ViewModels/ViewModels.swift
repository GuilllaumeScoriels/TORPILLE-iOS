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
import UIKit

struct LegalAcceptanceDraft {
    var acceptsEULA = false
    var acceptsPrivacyPolicy = false
    var canContinue: Bool { acceptsEULA && acceptsPrivacyPolicy }
}

enum DeviceLegalAcceptance {
    static let currentVersion = "2026-09-27"
    static let eulaVersionKey = "acceptedEULAVersion"
    static let privacyPolicyVersionKey = "acceptedPrivacyPolicyVersion"
    private static let fallbackInstallationIdentifierKey = "legalFallbackInstallationIdentifier"

    static var currentAcceptanceValue: String {
        let defaults = UserDefaults.standard
        let deviceIdentifier: String
        if let identifierForVendor = UIDevice.current.identifierForVendor?.uuidString {
            deviceIdentifier = identifierForVendor
        } else if let storedFallback = defaults.string(forKey: fallbackInstallationIdentifierKey) {
            deviceIdentifier = storedFallback
        } else {
            let newFallback = UUID().uuidString
            defaults.set(newFallback, forKey: fallbackInstallationIdentifierKey)
            deviceIdentifier = newFallback
        }
        return "\(currentVersion):\(deviceIdentifier)"
    }

    static var hasAcceptedCurrentVersion: Bool {
        hasAcceptedCurrentVersion(in: .standard)
    }

    static func hasAcceptedCurrentVersion(in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: eulaVersionKey) == currentAcceptanceValue
            && defaults.string(forKey: privacyPolicyVersionKey) == currentAcceptanceValue
    }

    @discardableResult
    static func record(_ acceptance: LegalAcceptanceDraft, in defaults: UserDefaults = .standard) -> Bool {
        guard acceptance.canContinue else { return false }
        defaults.set(currentAcceptanceValue, forKey: eulaVersionKey)
        defaults.set(currentAcceptanceValue, forKey: privacyPolicyVersionKey)
        return true
    }

}
import UniformTypeIdentifiers

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
            || message.localizedCaseInsensitiveContains("profil n’est pas encore configuré")
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
    private var pendingNotificationCommunityId: String?
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

        guard DeviceLegalAcceptance.hasAcceptedCurrentVersion else {
            env.notificationCenterService.stop()
            try? env.authRepository.signOut()
            route = .auth
            return
        }

        async let initialProfile = env.userRepository.getMeOrThrow()
        do {
            try await env.authRepository.reloadCurrentUser()
            try await env.authRepository.refreshIDToken(forcingRefresh: false)
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
            let me = try await initialProfile
            if let communityId = pendingNotificationCommunityId, me.hasRequiredIdentity {
                pendingNotificationCommunityId = nil
                route = .community(communityId)
            } else if let communityId = pendingJoinCommunityId, me.hasRequiredIdentity {
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

        guard route != .auth, route != .splash else { return }
        Task {
            await resumePendingJoinIfPossible()
        }
    }

    func resumePendingJoinIfPossible() async {
        guard DeviceLegalAcceptance.hasAcceptedCurrentVersion,
              !env.authRepository.currentUID.isEmpty,
              env.authRepository.isCurrentUserEmailVerified else {
            route = .auth
            return
        }
        do {
            let me = try await env.userRepository.getMeOrThrow()
            if !me.hasRequiredIdentity {
                route = .profile
            } else if let communityId = pendingJoinCommunityId {
                route = .join(communityId)
            } else {
                route = .home
            }
        } catch {
            route = isMissingProfileError(error) ? .profile : .auth
        }
    }

    func clearPendingJoin() {
        pendingJoinCommunityId = nil
    }

    func returnToInitialAuthentication() {
        pendingJoinCommunityId = nil
        env.notificationCenterService.resetForSignedOutUser()
        route = .auth
    }


    func openNotificationCenter() {
        env.notificationCenterService.markAllAsRead()
        route = .notificationCenter
    }

    func openCommunityFromNotification(_ communityId: String) {
        let cleanCommunityId = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCommunityId.isEmpty else { return }
        pendingNotificationCommunityId = cleanCommunityId
        guard route != .auth, route != .splash, route != .profile else { return }
        guard DeviceLegalAcceptance.hasAcceptedCurrentVersion,
              env.authRepository.isCurrentUserEmailVerified,
              !env.authRepository.currentUID.isEmpty else {
            route = .auth
            return
        }
        pendingNotificationCommunityId = nil
        route = .community(cleanCommunityId)
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
    @Published var passwordConfirmation = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var infoMessage: String?

    private let authRepository: AuthRepository
    private let languageService: AppLanguageService

    init(authRepository: AuthRepository, languageService: AppLanguageService) {
        self.authRepository = authRepository
        self.languageService = languageService
    }

    func signIn(hasAcceptedRequiredDocuments: Bool, onSuccess: @escaping () -> Void) {
        guard hasAcceptedRequiredDocuments && DeviceLegalAcceptance.hasAcceptedCurrentVersion else {
            error = languageService.phrase("Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.")
            return
        }
        guard let cleanEmail = validatedEmail() else { return }
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPassword.isEmpty else {
            error = "Renseigne ton mot de passe."
            return
        }

        run(onSuccess: onSuccess) {
            try await self.authRepository.signIn(email: cleanEmail, password: cleanPassword)
            try await self.authRepository.reloadCurrentUser()
            try await self.authRepository.refreshIDToken()
            guard self.authRepository.isCurrentUserEmailVerified else {
                defer { try? self.authRepository.signOut() }
                self.authRepository.setLanguageCode(self.languageService.firebaseAuthLanguageCode)
                try await self.authRepository.sendEmailVerification()
                throw TorpilleError.missingData(
                    self.languageService.localizedEmailNotVerified(for: cleanEmail)
                )
            }
        }
    }

    func signUp(hasAcceptedRequiredDocuments: Bool, onSuccess: @escaping () -> Void) {
        guard hasAcceptedRequiredDocuments && DeviceLegalAcceptance.hasAcceptedCurrentVersion else {
            error = languageService.phrase("Lis et accepte les règles EULA et la politique de confidentialité avant de continuer.")
            return
        }
        guard let cleanEmail = validatedEmail() else { return }
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPassword.count >= 6 else {
            error = "Choisis un mot de passe d'au moins 6 caractères."
            return
        }
        let cleanPasswordConfirmation = passwordConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPassword == cleanPasswordConfirmation else {
            error = languageService.text(.authPasswordsMismatch)
            return
        }

        run(onSuccess: {}) {
            do {
                try await self.authRepository.signUp(email: cleanEmail, password: cleanPassword)
            } catch {
                let authError = error as NSError
                guard authError.domain == AuthErrorDomain,
                      authError.code == AuthErrorCode.emailAlreadyInUse.rawValue else { throw error }
                // A repeated signup also renews verification for an existing account.
                // Authenticate first so a different password cannot trigger an email.
                try await self.authRepository.signIn(email: cleanEmail, password: cleanPassword)
            }
            defer { try? self.authRepository.signOut() }
            try await self.authRepository.reloadCurrentUser()
            guard !self.authRepository.isCurrentUserEmailVerified else {
                self.infoMessage = self.languageService.phrase("Ton adresse email est déjà vérifiée. Tu peux te connecter.")
                return
            }
            self.authRepository.setLanguageCode(self.languageService.firebaseAuthLanguageCode)
            try await self.authRepository.sendEmailVerification()
            self.infoMessage = self.languageService.localizedVerificationEmailSent(to: cleanEmail)
        }
    }

    func resetPassword() {
        guard !isLoading else { return }
        guard let cleanEmail = validatedEmail(emptyMessage: languageService.localizedResetPasswordPrompt()) else { return }

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

    private func normalizedEmail() -> String {
        email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private func validatedEmail(emptyMessage: String = "Renseigne ton email.") -> String? {
        let cleanEmail = normalizedEmail()
        email = cleanEmail

        guard !cleanEmail.isEmpty else {
            error = emptyMessage
            return nil
        }

        guard cleanEmail.contains("@"),
              cleanEmail.contains("."),
              cleanEmail.range(of: #"^\S+@\S+\.\S+$"#, options: .regularExpression) != nil else {
            error = "Adresse email invalide. Vérifie le format, par exemple nom@example.com."
            return nil
        }

        error = nil
        return cleanEmail
    }

    private func run(onSuccess: @escaping () -> Void, _ block: @escaping () async throws -> Void) {
        guard !isLoading else { return }
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
                    self.error = self.userFacingAuthError(nsError)
                }
            }
        }
    }

    private func userFacingAuthError(_ error: NSError) -> String {
        if error.domain == "FIRAuthErrorDomain" {
            switch error.code {
            case 17008:
                return "Adresse email invalide. Vérifie le format, par exemple nom@example.com."
            case 17009:
                return "Mot de passe incorrect."
            case 17011:
                return "Aucun compte ne correspond à cet email."
            case 17010:
                return languageService.phrase("Trop de tentatives. Patiente quelques instants avant de renvoyer un email.")
            case 17020:
                return "Connexion réseau indisponible. Réessaie dans quelques secondes."
            default:
                break
            }
        }

        return error.localizedDescription
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var pseudo = ""
    @Published var birthDate: Date?
    @Published var sex: ProfileSex?
    @Published var city = ""
    @Published var bio = ""
    @Published var isSaving = false
    @Published var error: String?
    @Published var selectedPhotoData: Data?
    @Published var selectedProfileIcon = "🎯"
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var acceptsEULA = false
    @Published private(set) var acceptsPrivacyPolicy = false
    
    private let repo: UserRepository
    private let authRepository: AuthRepository

    var email: String {
        authRepository.currentEmail
    }

    init(repo: UserRepository, authRepository: AuthRepository) {
        self.repo = repo
        self.authRepository = authRepository
        let defaults = UserDefaults.standard
        acceptsEULA = defaults.string(forKey: DeviceLegalAcceptance.eulaVersionKey) == DeviceLegalAcceptance.currentAcceptanceValue
        acceptsPrivacyPolicy = defaults.string(forKey: DeviceLegalAcceptance.privacyPolicyVersionKey) == DeviceLegalAcceptance.currentAcceptanceValue
    }

    func loadExistingProfile() async {
        guard let profile = try? await repo.getMeOrThrow() else { return }
        firstName = profile.firstName
        lastName = profile.lastName
        pseudo = profile.pseudo
        birthDate = profile.birthDate?.dateValue()
        sex = profile.sex
        city = profile.city ?? ""
        bio = profile.bio ?? ""
        selectedProfileIcon = profile.profileIcon ?? selectedProfileIcon
        let defaults = UserDefaults.standard
        acceptsEULA = defaults.string(forKey: DeviceLegalAcceptance.eulaVersionKey) == DeviceLegalAcceptance.currentAcceptanceValue
        acceptsPrivacyPolicy = defaults.string(forKey: DeviceLegalAcceptance.privacyPolicyVersionKey) == DeviceLegalAcceptance.currentAcceptanceValue
    }

    var acceptsRequiredDocuments: Bool { acceptsEULA && acceptsPrivacyPolicy && DeviceLegalAcceptance.hasAcceptedCurrentVersion }

    func acceptEULA() { acceptsEULA = true }


    var canSubmitProfile: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (selectedPhotoData != nil || !selectedProfileIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && acceptsRequiredDocuments
    }

    func save(onDone: @escaping () -> Void) {
        error = nil
        guard canSubmitProfile else {
            showCompletionRequirement()
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await repo.updateProfile(
                    firstName: firstName,
                    lastName: lastName,
                    pseudo: pseudo,
                    birthDate: birthDate,
                    sex: sex,
                    city: city,
                    bio: bio,
                    imageData: selectedPhotoData,
                    profileIcon: selectedPhotoData == nil ? selectedProfileIcon : nil,
                    acceptsTerms: acceptsRequiredDocuments
                )
                let me = try await repo.getMeOrThrow()
                guard me.hasRequiredIdentity else {
                    throw TorpilleError.missingData("Le profil a été enregistré mais reste incomplet.")
                }
                onDone()
            } catch {
                let nsError = error as NSError
                if case TorpilleError.pseudoAlreadyUsed = error {
                    self.error = TorpilleError.pseudoAlreadyUsed.localizedDescription
                } else if nsError.domain == FirestoreErrorDomain,
                   nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                    self.error = "L'enregistrement du profil est refusé par Firestore. Déploie les règles Firestore à jour puis réessaie."
                } else {
                    self.error = debugErrorMessage(error)
                }
            }
        }
    }

    func showCompletionRequirement() {
        error = "Complète obligatoirement ton prénom, ton nom et ton pseudo, puis accepte les règles EULA et la politique de confidentialité avant de continuer."
    }

    func cancelSetup(onDone: @escaping () -> Void) {
        do {
            try authRepository.signOut()
            onDone()
        } catch {
            self.error = debugErrorMessage(error)
        }
    }

    func deleteIncompleteAccount(onDone: @escaping () -> Void) {
        guard !isDeletingAccount else { return }
        error = nil
        isDeletingAccount = true

        Task {
            defer { isDeletingAccount = false }
            do {
                try await authRepository.reloadCurrentUser()
                try await authRepository.refreshIDToken()
                do {
                    try await repo.deleteCurrentAccountServerSide()
                } catch {
                    // A verified account that has not completed onboarding owns
                    // little or no Firestore data. If an older backend revision
                    // fails its cleanup, still remove Firebase Auth so the email
                    // is released and a future signup must verify it again.
                    try await authRepository.deleteCurrentUser()
                }
                try? authRepository.signOut()
                onDone()
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var isLoadingProfile = true
    @Published var isLoadingCommunities = true
    @Published var me: UserProfile?
    @Published var communities: [Community] = []
    @Published var error: String?
    @Published var infoMessage: String?
    @Published var profileSaveMessage: String?
    @Published var profileSaveSucceeded = false
    @Published var isDeletingAccount = false
    @Published var blockedUsers: [BlockedUser] = []
    @Published var friends: [PublicFriend] = []
    @Published var friendSearchResults: [UserProfile] = []
    @Published var isSearchingFriends = false
    @Published var selectedPublicProfile: UserProfile?

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
        guard meRegistration == nil else { return }

        meRegistration = userRepository.observeMe { [weak self] profile in
            DispatchQueue.main.async {
                self?.me = profile
                self?.isLoadingProfile = false
            }
        }
        communitiesRegistration = communityRepository.observeCommunitiesForMe(onPartial: { [weak self] values in
            DispatchQueue.main.async {
                guard self?.isLoadingCommunities == true else { return }
                self?.communities = values
            }
        }, handler: { [weak self] values in
            DispatchQueue.main.async {
                self?.communities = values
                self?.isLoadingCommunities = false
            }
        })
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

    func saveProfile(firstName: String, lastName: String, pseudo: String, birthDate: Date?, sex: ProfileSex?, city: String, bio: String, imageData: Data?, profileIcon: String?, acceptsTerms: Bool) async -> Bool {
        error = nil
        infoMessage = nil
        profileSaveMessage = nil
        profileSaveSucceeded = false
        do {
            try await userRepository.updateProfile(
                firstName: firstName,
                lastName: lastName,
                pseudo: pseudo,
                birthDate: birthDate,
                sex: sex,
                city: city,
                bio: bio,
                imageData: imageData,
                profileIcon: profileIcon,
                acceptsTerms: acceptsTerms
            )
            let refreshedProfile = try await userRepository.getMeOrThrow()
            guard refreshedProfile.hasRequiredIdentity else {
                throw TorpilleError.missingData(
                    "Profil encore incomplet : \(refreshedProfile.missingRequiredProfileFields.joined(separator: ", "))."
                )
            }
            infoMessage = "Profil mis à jour."
            profileSaveMessage = "Profil mis à jour."
            profileSaveSucceeded = true
            return true
        } catch {
            let nsError = error as NSError
            if nsError.domain == "UserRepository" && nsError.code == 409 {
                self.error = "Ce pseudo est déjà utilisé."
            } else {
                self.error = debugErrorMessage(error)
            }
            profileSaveMessage = self.error
            profileSaveSucceeded = false
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
        Task {
            _ = await sendFriendRequestAndWait(to: profile)
        }
    }

    func sendFriendRequestAndWait(to profile: UserProfile) async -> Bool {
        error = nil
        infoMessage = nil
        do {
            try await userRepository.sendFriendRequest(to: profile)
            infoMessage = "Demande d'ami envoyée à @\(profile.pseudo)."
            return true
        } catch {
            self.error = debugErrorMessage(error)
            return false
        }
    }

    func removeFriendAndWait(_ friend: PublicFriend) async -> Bool {
        error = nil
        infoMessage = nil
        do {
            try await userRepository.removeFriend(friend)
            infoMessage = "@\(friend.pseudo) a été retiré de tes amis."
            return true
        } catch {
            self.error = debugErrorMessage(error)
            return false
        }
    }

    func openPublicProfile(for friend: PublicFriend) {
        error = nil
        Task {
            do {
                selectedPublicProfile = try await communityRepository.publicUserProfile(uid: friend.uid)
            } catch {
                selectedPublicProfile = UserProfile(
                    uid: friend.uid,
                    email: "",
                    pseudo: friend.pseudo,
                    pseudoKey: "",
                    photoUrl: friend.photoUrl,
                    profileIcon: friend.profileIcon,
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

                // La Cloud Function vient de supprimer l'utilisateur Firebase Auth.
                // La déconnexion locale reste nécessaire, mais elle ne doit pas empêcher
                // le retour à l'écran initial si Firebase considère déjà la session invalide.
                try? authRepository.signOut()
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
    @Published var selectedPublicProfile: UserProfile?

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

    func openPublicProfile(_ player: UserProfile) {
        selectedPublicProfile = player
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
                if let torpilleError = error as? TorpilleError,
                   case .missingData(let message) = torpilleError {
                    self.error = message
                } else if isMissingProfileError(error) {
                    self.error = "Ton profil n'existe plus ou n'est pas encore terminé. Ouvre l'écran Profil et complète les informations obligatoires, puis réessaie."
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
    @Published var infoMessage: String?

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
            let outcome = try await repo.joinCommunity(communityId: communityId, me: me)
            switch outcome {
            case .joined:
                onJoined()
            case .requestPending:
                infoMessage = "Ta demande a été envoyée à l'administrateur. Tu recevras une notification après sa décision."
            }
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
    @Published var friends: [PublicFriend] = []
    @Published var savedMessageCount = 0
    @Published var responseHours = 1
    @Published var responseMinutes = 0
    @Published var isPublic = true
    @Published var rawAllowlist = ""
    @Published var error: String?
    @Published var infoMessage: String?
    @Published var selectedPublicProfile: UserProfile?
    @Published var hiddenMemberIds: Set<String> = []
    @Published var pendingJoinRequests: [CommunityJoinRequest] = []
    @Published var isDeletingCommunity = false

    private let repo: CommunityRepository
    private let userRepo: UserRepository
    private var communityRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var savedMessagesRegistration: ListenerRegistration?
    private var friendsRegistration: ListenerRegistration?
    private var hiddenMembersRegistration: ListenerRegistration?
    private var joinRequestsRegistration: ListenerRegistration?

    init(repo: CommunityRepository, userRepo: UserRepository) {
        self.repo = repo
        self.userRepo = userRepo
    }

    func start(communityId: String) {
        communityRegistration?.remove()
        membersRegistration?.remove()
        savedMessagesRegistration?.remove()
        hiddenMembersRegistration?.remove()
        joinRequestsRegistration?.remove()
        hiddenMemberIds = []

        communityRegistration = repo.observeCommunity(communityId) { [weak self] value in
            DispatchQueue.main.async {
                self?.community = value
                self?.isPublic = value?.isPublic ?? true
                let components = splitResponseTime(value?.responseTimeSeconds ?? 3600)
                self?.responseHours = components.hours
                self?.responseMinutes = components.minutes
                self?.joinRequestsRegistration?.remove()
                self?.joinRequestsRegistration = nil
                if value?.adminUid == self?.repo.currentUID {
                    self?.joinRequestsRegistration = self?.repo.observePendingJoinRequests(communityId: communityId) { [weak self] values in
                        DispatchQueue.main.async { self?.pendingJoinRequests = values }
                    }
                } else {
                    self?.pendingJoinRequests = []
                }
            }
        }

        membersRegistration = repo.observeDiscussionParticipants(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.members = values
            }
        }

        savedMessagesRegistration = repo.observeSavedMessages(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.savedMessageCount = values.count
            }
        }

        hiddenMembersRegistration = repo.observeHiddenMemberIds(communityId: communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.hiddenMemberIds = values
            }
        }

        friendsRegistration = userRepo.observeFriends { [weak self] values in
            DispatchQueue.main.async {
                self?.friends = values
            }
        }

    }

    func resolveJoinRequest(_ request: CommunityJoinRequest, accept: Bool) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.resolveJoinRequest(request, accept: accept)
                infoMessage = accept
                    ? "@\(request.requesterPseudo) a rejoint la communauté."
                    : "La demande de @\(request.requesterPseudo) a été refusée."
            } catch {
                self.error = debugErrorMessage(error)
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

    func deleteCommunity(communityId: String, onDeleted: @escaping () -> Void) {
        guard !isDeletingCommunity else { return }
        error = nil
        infoMessage = nil
        isDeletingCommunity = true
        Task {
            defer { isDeletingCommunity = false }
            do {
                try await repo.deleteCommunityPermanently(communityId: communityId)
                onDeleted()
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    var canModerateMembers: Bool {
        guard let community else { return false }
        return community.adminUid == repo.currentUID
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

    func showContentFromMember(communityId: String, member: Member) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.showMemberContent(communityId: communityId, memberUid: member.uid)
                infoMessage = "Les contenus de @\(member.displayName) sont réaffichés dans cette communauté."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func isContentHidden(for member: Member) -> Bool {
        hiddenMemberIds.contains(member.uid)
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

    func reportMember(communityId: String, member: Member, reason: ReportReason, details: String) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.reportContent(
                    communityId: communityId,
                    contentId: member.uid,
                    contentType: .profile,
                    authorUid: member.uid,
                    authorPseudo: member.displayName,
                    reason: reason,
                    details: details
                )
                infoMessage = "Signalement envoyé. Une confirmation te sera transmise."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sendFriendRequest(to member: Member) {
        error = nil
        infoMessage = nil
        Task {
            do {
                let profile = try await repo.publicUserProfile(uid: member.uid)
                try await userRepo.sendFriendRequest(to: profile)
                infoMessage = "Demande d'ami envoyée à @\(profile.pseudo)."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func isFriend(_ member: Member) -> Bool {
        friends.contains { $0.uid == member.uid }
    }

    func openPublicProfile(for member: Member) {
        error = nil
        Task {
            do {
                selectedPublicProfile = try await repo.publicUserProfile(uid: member.uid)
            } catch {
                selectedPublicProfile = UserProfile(
                    uid: member.uid,
                    email: "",
                    pseudo: member.displayName,
                    pseudoKey: "",
                    photoUrl: member.photoUrl,
                    profileIcon: member.profileIcon,
                    communityIds: [],
                    pinnedCommunityIds: [],
                    communityXP: [:],
                    xpTotal: member.xpInCommunity,
                    fcmToken: nil,
                    termsAcceptedAt: nil,
                    moderationRulesAcceptedAt: nil,
                    updatedAt: nil
                )
            }
        }
    }

    deinit {
        communityRegistration?.remove()
        membersRegistration?.remove()
        savedMessagesRegistration?.remove()
        friendsRegistration?.remove()
        hiddenMembersRegistration?.remove()
    }
}

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published var isLoadingMessages = true
    @Published var community: Community?
    @Published var messages: [Message] = []
    @Published var members: [Member] = []
    @Published var torpilleTargetMembers: [Member] = []
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
    @Published var selectedPublicProfile: UserProfile?

    private let communityRepo: CommunityRepository
    private let userRepo: UserRepository
    private var communityRegistration: ListenerRegistration?
    private var messagesRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var torpilleTargetMembersRegistration: ListenerRegistration?
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
        torpilleTargetMembersRegistration?.remove()
        myMemberRegistration?.remove()
        meRegistration?.remove()
        torpillesRegistration?.remove()
        didCaptureInitialConnectionDate = false
        unreadReferenceDate = nil
        firstUnreadMessageId = nil
        lastMarkedMessageTimestamp = nil

        meRegistration = userRepo.observeMe { [weak self] value in
            DispatchQueue.main.async { self?.me = value }
        }
        communityRegistration = communityRepo.observeCommunity(communityId) { [weak self] value in
            DispatchQueue.main.async { self?.community = value }
        }
        messagesRegistration = communityRepo.observeMessages(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.messages = values
                self?.isLoadingMessages = false
                self?.refreshUnreadMessages()
            }
        }
        membersRegistration = communityRepo.observeMembers(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.members = values
            }
        }
        torpilleTargetMembersRegistration = communityRepo.observeTorpilleTargetMembers(communityId) { [weak self] values in
            DispatchQueue.main.async {
                self?.torpilleTargetMembers = values
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
                    self.myMember = initialMember
                    self.refreshUnseenTorpilles()
                    self.refreshUnreadMessages()
                    self.observeMyMemberChanges(communityId: communityId)
                }
                try await communityRepo.markCommunityOpened(communityId)
                try await communityRepo.syncXPState(communityId: communityId)
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    private func observeMyMemberChanges(communityId: String) {
        myMemberRegistration?.remove()
        myMemberRegistration = communityRepo.observeMyMember(communityId) { [weak self] value in
            DispatchQueue.main.async {
                self?.myMember = value
                self?.refreshUnseenTorpilles()
                self?.refreshUnreadMessages()
            }
        }
    }

    private func captureUnreadReferenceDate(from member: Member?) {
        unreadReferenceDate = member?.lastOpenedAt?.dateValue()
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
        let threshold = didCaptureInitialConnectionDate
            ? (unreadReferenceDate ?? .distantPast)
            : (myMember?.lastOpenedAt?.dateValue() ?? .distantPast)
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
            defer {
                self.isSending = false
                try? FileManager.default.removeItem(at: fileURL)
            }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                if isImageMedia(fileURL) {
                    try await communityRepo.sendImageMessage(communityId: communityId, senderPseudo: senderPseudo, localFileURL: fileURL)
                } else {
                    try await communityRepo.sendCapturedVideoMessage(communityId: communityId, senderPseudo: senderPseudo, localFileURL: fileURL)
                }
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func sendCapturedMediaBatch(communityId: String, fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        error = nil
        infoMessage = nil
        isSending = true
        Task {
            defer {
                self.isSending = false
                fileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                for fileURL in fileURLs {
                    if isImageMedia(fileURL) {
                        try await communityRepo.sendImageMessage(
                            communityId: communityId,
                            senderPseudo: senderPseudo,
                            localFileURL: fileURL
                        )
                    } else {
                        try await communityRepo.sendCapturedVideoMessage(
                            communityId: communityId,
                            senderPseudo: senderPseudo,
                            localFileURL: fileURL
                        )
                    }
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    private func isImageMedia(_ fileURL: URL) -> Bool {
        UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .image) == true
    }

    func sendAudioMessage(communityId: String, fileURL: URL, durationSeconds: Double) {
        error = nil
        infoMessage = nil
        isSending = true
        Task {
            defer {
                self.isSending = false
                try? FileManager.default.removeItem(at: fileURL)
            }
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
        guard let taggedMember else {
            error = "Choisis un membre de la communauté avant d'envoyer la torpille."
            return
        }

        error = nil
        infoMessage = nil
        isSending = true
        Task {
            defer {
                self.isSending = false
                try? FileManager.default.removeItem(at: fileURL)
            }
            do {
                let senderPseudo = try await resolveSenderPseudo()
                try await communityRepo.sendVideoTorpille(
                    communityId: communityId,
                    senderPseudo: senderPseudo,
                    localFileURL: fileURL,
                    taggedUid: taggedMember.uid,
                    taggedPseudo: taggedMember.displayName.isEmpty ? cleanFallbackPseudoText : taggedMember.displayName,
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
            defer {
                self.isSending = false
                try? FileManager.default.removeItem(at: fileURL)
            }
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

    func openPublicProfile(for message: Message) {
        error = nil
        let member = members.first { $0.uid == message.senderUid }
        Task {
            do {
                selectedPublicProfile = try await communityRepo.publicUserProfile(uid: message.senderUid)
            } catch {
                selectedPublicProfile = UserProfile(
                    uid: message.senderUid,
                    email: "",
                    pseudo: message.senderPseudo,
                    pseudoKey: "",
                    photoUrl: member?.photoUrl,
                    profileIcon: member?.profileIcon,
                    communityIds: [],
                    pinnedCommunityIds: [],
                    communityXP: [:],
                    xpTotal: member?.xpInCommunity ?? 0,
                    fcmToken: nil,
                    termsAcceptedAt: nil,
                    moderationRulesAcceptedAt: nil,
                    updatedAt: nil
                )
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
        torpilleTargetMembersRegistration?.remove()
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

    func canReport(_ reel: PublishedReel) -> Bool {
        !reel.authorUid.isEmpty && reel.authorUid != repo.currentUID
    }

    func report(_ reel: PublishedReel, reason: ReportReason, details: String) {
        error = nil
        infoMessage = nil
        Task {
            do {
                try await repo.reportContent(
                    communityId: reel.communityId,
                    contentId: reel.stableId,
                    contentType: .reel,
                    authorUid: reel.authorUid,
                    authorPseudo: reel.authorPseudo,
                    reason: reason,
                    details: details
                )
                infoMessage = "Signalement envoyé. Notre équipe vérifie ce contenu."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
    }

    func blockAuthor(of reel: PublishedReel) {
        guard canReport(reel) else { return }
        error = nil
        infoMessage = nil
        Task {
            do {
                let member = Member(
                    uid: reel.authorUid,
                    pseudo: reel.authorPseudo,
                    photoUrl: reel.authorPhotoUrl,
                    profileIcon: reel.authorProfileIcon
                )
                try await repo.blockUser(member)
                infoMessage = "@\(reel.authorPseudo) a été bloqué. Ses contenus sont désormais masqués."
            } catch {
                self.error = debugErrorMessage(error)
            }
        }
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
    @Published var hasPublishedMyLocation = false
    @Published var myLocationAnnotation: MapMemberAnnotation?
    @Published var isSendingTorpille = false
    @Published var selectedPublicProfile: UserProfile?
    @Published private(set) var isGhostMode: Bool
    @Published private(set) var isUpdatingGhostMode = false

    private let repo: CommunityRepository
    private let userRepository: UserRepository
    private let locationService: LocationService
    private let languageService: AppLanguageService
    private var communitiesRegistration: ListenerRegistration?
    private var membersRegistration: ListenerRegistration?
    private var sharedCommunityRegistrations: [String: ListenerRegistration] = [:]
    private var memberUIDsByCommunity: [String: Set<String>] = [:]
    private var membersByCommunity: [String: [Member]] = [:]
    private var didRequestLocationAfterCommunitiesLoaded = false
    private var hasLoadedGhostModeFromServer = false

    init(repo: CommunityRepository, userRepository: UserRepository, locationService: LocationService, languageService: AppLanguageService) {
        self.repo = repo
        self.userRepository = userRepository
        self.locationService = locationService
        self.languageService = languageService
        self.isGhostMode = UserDefaults.standard.bool(forKey: Self.ghostModeStorageKey(for: repo.currentUID))
    }

    var currentUserId: String {
        repo.currentUID
    }

    func start() {
        communitiesRegistration?.remove()
        removeSharedCommunityListeners()
        memberUIDsByCommunity = [:]
        membersByCommunity = [:]
        didRequestLocationAfterCommunitiesLoaded = false
        hasLoadedGhostModeFromServer = false

        Task {
            if let profile = try? await userRepository.getMeOrThrow() {
                isGhostMode = profile.isGhostMode
                UserDefaults.standard.set(profile.isGhostMode, forKey: Self.ghostModeStorageKey(for: currentUserId))
                if profile.isGhostMode {
                    myLocationAnnotation = nil
                    hasPublishedMyLocation = false
                }
            }
            hasLoadedGhostModeFromServer = true
            if !isGhostMode, !communities.isEmpty, !didRequestLocationAfterCommunitiesLoaded {
                didRequestLocationAfterCommunitiesLoaded = true
                refreshLocation()
            }
        }

        communitiesRegistration = repo.observeCommunitiesForMe { [weak self] values in
            DispatchQueue.main.async {
                guard let self else { return }
                self.communities = values
                self.updateSharedCommunityListeners(with: values)
                if values.contains(where: { $0.stableId == self.selectedCommunityId }) == false {
                    if values.first != nil {
                        self.selectedCommunityId = ""
                        self.members = self.allSharedMembers
                    } else {
                        self.selectedCommunityId = ""
                        self.members = []
                    }
                } else if self.selectedCommunityId.isEmpty {
                    self.members = self.allSharedMembers
                }
                if !values.isEmpty
                    && self.hasLoadedGhostModeFromServer
                    && !self.didRequestLocationAfterCommunitiesLoaded
                    && !self.isGhostMode {
                    self.didRequestLocationAfterCommunitiesLoaded = true
                    self.refreshLocation()
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
        guard !isGhostMode else { return }
        error = nil
        Task {
            do {
                let location = try await locationService.currentLocation()
                let knownCommunityIds = communities.map(\.stableId).filter { !$0.isEmpty }
                let communityIds = knownCommunityIds.isEmpty ? (try await repo.myCommunityIds()) : knownCommunityIds
                let didPublish = try await repo.updateMyLocation(in: communityIds, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                guard didPublish else {
                    self.isGhostMode = true
                    self.myLocationAnnotation = nil
                    self.hasPublishedMyLocation = false
                    UserDefaults.standard.set(true, forKey: Self.ghostModeStorageKey(for: self.currentUserId))
                    return
                }
                let profile = try? await userRepository.getMeOrThrow()
                let pseudo = profile?.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayPseudo = (pseudo?.isEmpty == false ? pseudo : nil) ?? "Moi"
                self.myLocationAnnotation = MapMemberAnnotation(
                    id: self.currentUserId,
                    pseudo: displayPseudo,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    subtitle: languageService.myCurrentLocationLabel,
                    photoUrl: profile?.photoUrl,
                    profileIcon: profile?.profileIcon,
                    lastTorpilleTimeText: ""
                )
                self.hasPublishedMyLocation = true
            } catch {
                self.hasPublishedMyLocation = false
                self.error = error.localizedDescription
            }
        }
    }

    func setGhostMode(_ enabled: Bool) {
        guard enabled != isGhostMode, !isUpdatingGhostMode else { return }
        let previousValue = isGhostMode
        isGhostMode = enabled
        myLocationAnnotation = enabled ? nil : myLocationAnnotation
        UserDefaults.standard.set(enabled, forKey: Self.ghostModeStorageKey(for: currentUserId))
        error = nil
        isUpdatingGhostMode = true

        Task {
            defer { isUpdatingGhostMode = false }
            do {
                let communityIds = communities.map(\.stableId).filter { !$0.isEmpty }
                try await repo.setGhostMode(enabled, in: communityIds)
                if !enabled {
                    refreshLocation()
                }
            } catch {
                isGhostMode = previousValue
                UserDefaults.standard.set(previousValue, forKey: Self.ghostModeStorageKey(for: currentUserId))
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

    func openPublicProfile(for member: MapMemberAnnotation) {
        error = nil
        Task {
            do {
                selectedPublicProfile = try await repo.publicUserProfile(uid: member.id)
            } catch {
                selectedPublicProfile = UserProfile(
                    uid: member.id,
                    email: "",
                    pseudo: member.pseudo,
                    pseudoKey: "",
                    photoUrl: member.photoUrl,
                    profileIcon: member.profileIcon,
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

    var annotations: [MapMemberAnnotation] {
        guard !isGhostMode else { return [] }
        var values = filteredMembers.compactMap { member -> MapMemberAnnotation? in
            guard let latitude = member.lastLatitude, let longitude = member.lastLongitude else { return nil }
            return MapMemberAnnotation(
                id: member.id,
                pseudo: member.displayName,
                latitude: latitude,
                longitude: longitude,
                subtitle: languageService.mapMemberSubtitle(
                    lastTorpilledAt: member.lastTorpilledAt,
                    locationUpdatedAt: member.lastLocationUpdatedAt
                ),
                photoUrl: member.photoUrl,
                profileIcon: member.profileIcon,
                lastTorpilleTimeText: member.mapLastTorpilleTimeText
            )
        }
        if let myLocationAnnotation {
            values.removeAll { $0.id == myLocationAnnotation.id }
            values.append(myLocationAnnotation)
        }
        return values
    }

    private static func ghostModeStorageKey(for uid: String) -> String {
        "torpille.ghostMode.\(uid.isEmpty ? "anonymous" : uid)"
    }

    var visibleMembersCount: Int {
        annotations.count
    }

    private var filteredMembers: [Member] {
        let sourceMembers = selectedCommunityId.isEmpty ? allSharedMembers : members
        guard showOnlyRecentlyConnected else {
            return sourceMembers
        }
        let limitDate = Date().addingTimeInterval(-1800)
        return sourceMembers.filter { member in
            let activityDate = member.lastActiveAt?.dateValue() ?? member.lastOpenedAt?.dateValue()
            guard let activityDate else { return false }
            return activityDate >= limitDate
        }
    }

    private var allSharedMembers: [Member] {
        let uniqueMembers = membersByCommunity.values
            .flatMap { $0 }
            .reduce(into: [String: Member]()) { partialResult, member in
                if let existing = partialResult[member.uid] {
                    partialResult[member.uid] = mergeMapMember(existing, with: member)
                } else {
                    partialResult[member.uid] = member
                }
            }
        return uniqueMembers.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func mergeMapMember(_ existing: Member, with incoming: Member) -> Member {
        var merged = existing

        if merged.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.pseudo = incoming.pseudo
        }
        merged.photoUrl = merged.photoUrl ?? incoming.photoUrl
        merged.profileIcon = merged.profileIcon ?? incoming.profileIcon
        merged.xpInCommunity = max(merged.xpInCommunity, incoming.xpInCommunity)
        merged.lastTorpilledAt = newestTimestamp(merged.lastTorpilledAt, incoming.lastTorpilledAt)
        merged.lastTorpilleSentAt = newestTimestamp(merged.lastTorpilleSentAt, incoming.lastTorpilleSentAt)
        merged.lastOpenedAt = newestTimestamp(merged.lastOpenedAt, incoming.lastOpenedAt)
        merged.lastActiveAt = newestTimestamp(merged.lastActiveAt, incoming.lastActiveAt)

        let existingLocationDate = merged.lastLocationUpdatedAt?.dateValue() ?? .distantPast
        let incomingLocationDate = incoming.lastLocationUpdatedAt?.dateValue() ?? .distantPast
        if merged.lastLatitude == nil
            || merged.lastLongitude == nil
            || incomingLocationDate >= existingLocationDate {
            merged.lastLatitude = incoming.lastLatitude ?? merged.lastLatitude
            merged.lastLongitude = incoming.lastLongitude ?? merged.lastLongitude
            merged.lastLocationUpdatedAt = newestTimestamp(merged.lastLocationUpdatedAt, incoming.lastLocationUpdatedAt)
        }

        return merged
    }

    private func newestTimestamp(_ lhs: Timestamp?, _ rhs: Timestamp?) -> Timestamp? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left.dateValue() >= right.dateValue() ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
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
            sharedCommunityRegistrations[communityId] = repo.observeMembersForMap(communityId) { [weak self] members in
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
    private var hasSyncedInThisSession = false
    private var lastPresenceSyncAt: Date?

    init(authRepository: AuthRepository, repo: CommunityRepository) {
        self.authRepository = authRepository
        self.repo = repo
    }

    func syncOnAppOpenIfNeeded() async {
        guard !hasSyncedInThisSession else { return }
        guard !authRepository.currentUID.isEmpty else { return }
        hasSyncedInThisSession = true
        await syncPresenceIfPossible()
    }

    func syncOnAppActive() async {
        guard !authRepository.currentUID.isEmpty else { return }
        if let lastPresenceSyncAt, Date().timeIntervalSince(lastPresenceSyncAt) < 60 {
            return
        }
        await syncPresenceIfPossible()
    }

    private func syncPresenceIfPossible() async {
        lastError = nil

        do {
            let communityIds = try await repo.myCommunityIds()
            guard !communityIds.isEmpty else { return }
            try await repo.markMeActive(in: communityIds)
            lastPresenceSyncAt = Date()
        } catch {
            lastError = error.localizedDescription
            return
        }

        // Location is requested only from the map experience or when the user
        // explicitly disables ghost mode. Launching the app never causes a
        // protected-resource prompt.
    }
}
