import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import FirebaseStorage

enum CommunityCreationStep: String {
    case refreshToken = "refresh-token"
    case createCommunityDocument = "create-community-document"
    case createAdminMembership = "create-admin-membership"
    case recalculateTotalXP = "recalculate-total-xp"
}

enum OperationDiagnostics {
    static func message(for step: CommunityCreationStep, error: Error) -> String {
        let nsError = error as NSError
        var lines: [String] = [
            "Creation de communaute echouee a l'etape \(step.rawValue).",
            "Domaine: \(nsError.domain)",
            "Code: \(nsError.code)",
            "Description: \(nsError.localizedDescription)"
        ]

        if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] {
            lines.append("Raison: \(failureReason)")
        }

        if let details = nsError.userInfo["details"] {
            lines.append("Details: \(details)")
        }

        return lines.joined(separator: "\n")
    }
}

private func normalizedProfileImageData(from rawData: Data) -> Data? {
    guard let image = UIImage(data: rawData) else {
        return rawData
    }

    let maxDimension: CGFloat = 1_280
    let originalSize = image.size
    let longestSide = max(originalSize.width, originalSize.height)
    let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
    let targetSize = CGSize(
        width: max(1, originalSize.width * scale),
        height: max(1, originalSize.height * scale)
    )

    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let rendered = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }

    return rendered.jpegData(compressionQuality: 0.82)
}

private func debugDescribe(_ error: Error) -> String {
    let nsError = error as NSError
    return """
    domain = \(nsError.domain)
    code = \(nsError.code)
    description = \(nsError.localizedDescription)
    userInfo = \(nsError.userInfo)
    """
}

    private func debugLog(_ label: String, _ error: Error) {
        let nsError = error as NSError
        print("🔥 \(label)")
        print("domain =", nsError.domain)
        print("code =", nsError.code)
        print("userInfo =", nsError.userInfo)
    }

    private final class CompositeListenerRegistration: NSObject, ListenerRegistration {
        private var registrations: [ListenerRegistration]

        init(_ registrations: [ListenerRegistration]) {
            self.registrations = registrations
        }

        func remove() {
            registrations.forEach { $0.remove() }
            registrations.removeAll()
        }
    }

    private func stringArrayValue(from rawValue: Any?) -> [String] {
        guard let values = rawValue as? [Any] else { return [] }
        return values.compactMap { value in
            guard let stringValue = value as? String else { return nil }
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

enum CommunityMembershipStore {
    static func normalizedIDs(from rawValue: Any?, limit: Int? = nil) -> [String] {
        let values = stringArrayValue(from: rawValue)
        var cleaned: [String] = []
        for value in values where cleaned.contains(value) == false {
            cleaned.append(value)
            if let limit, cleaned.count >= limit {
                break
            }
        }
        return cleaned
    }

    static func mergedIDs(primary: [String], secondary: [String], limit: Int? = nil) -> [String] {
        normalizedIDs(from: primary + secondary, limit: limit)
    }
}

private func extractTotalXP(from data: [String: Any]) -> Int64 {
    if let value = data["xptotal"] as? Int64 { return value }
    if let value = data["xptotal"] as? Int { return Int64(value) }
    if let value = data["xptotal"] as? Double { return Int64(value) }
    if let value = data["xpTotal"] as? Int64 { return value }
    if let value = data["xpTotal"] as? Int { return Int64(value) }
    if let value = data["xpTotal"] as? Double { return Int64(value) }
    return 0
}

private func extractCommunityXP(from data: [String: Any]) -> [String: Int64] {
    guard let rawMap = data["communityXP"] as? [String: Any] else { return [:] }
    var result: [String: Int64] = [:]
    for (communityId, rawValue) in rawMap {
        let cleanId = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { continue }
        if let value = rawValue as? Int64 {
            result[cleanId] = value
        } else if let value = rawValue as? Int {
            result[cleanId] = Int64(value)
        } else if let value = rawValue as? Double {
            result[cleanId] = Int64(value)
        } else if let value = rawValue as? NSNumber {
            result[cleanId] = value.int64Value
        }
    }
    return result
}

private enum BasicContentFilter {
    private static let blockedTerms = [
        "porn", "porno", "xxx", "nude", "nudes", "sexe", "suicide",
        "kill yourself", "va te tuer", "pute", "connard", "salope"
    ]

    static func validate(_ text: String) throws {
        let normalized = normalizedForModeration(text)
        let compact = normalized.filter(\.isLetter)
        if blockedTerms.contains(where: { term in
            let normalizedTerm = normalizedForModeration(term)
            return normalized.contains(normalizedTerm)
                || compact.contains(normalizedTerm.filter(\.isLetter))
        }) {
            throw TorpilleError.missingData("Ce contenu ne respecte pas les règles de la communauté.")
        }
    }

    private static func normalizedForModeration(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "3", with: "e")
            .replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "5", with: "s")
            .replacingOccurrences(of: "7", with: "t")
    }
}

final class AuthRepository {
    private let auth = Auth.auth()

    var currentUID: String { auth.currentUser?.uid ?? "" }
    var currentEmail: String { auth.currentUser?.email ?? "" }
    var isCurrentUserEmailVerified: Bool { auth.currentUser?.isEmailVerified ?? false }
    var needsRecentLoginForAccountDeletion: Bool {
        guard let lastSignInDate = auth.currentUser?.metadata.lastSignInDate else {
            return false
        }
        return Date().timeIntervalSince(lastSignInDate) > 300
    }

    func signUp(email: String, password: String) async throws {
        print("📍 AuthRepository.signUp")
        print("📧 email =", email)
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            print("✅ signUp ok uid =", result.user.uid)
        } catch {
            debugLog("AuthRepository.signUp failed", error)
            throw error
        }
    }

    func sendEmailVerification() async throws {
        guard let user = auth.currentUser else {
            throw TorpilleError.notAuthenticated
        }
        try await user.sendEmailVerification()
    }

    func reloadCurrentUser() async throws {
        guard let user = auth.currentUser else {
            throw TorpilleError.notAuthenticated
        }
        try await user.reload()
    }

    func refreshIDToken(forcingRefresh: Bool = true) async throws {
        guard let user = auth.currentUser else {
            throw TorpilleError.notAuthenticated
        }
        _ = try await user.getIDTokenResult(forcingRefresh: forcingRefresh)
    }

    func signIn(email: String, password: String) async throws {
        print("📍 AuthRepository.signIn")
        print("📧 email =", email)
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            print("✅ signIn ok uid =", result.user.uid)
        } catch {
            debugLog("AuthRepository.signIn failed", error)
            throw error
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }

    func setLanguageCode(_ languageCode: String?) {
        auth.languageCode = languageCode
    }

    func signOut() throws {
        try auth.signOut()
    }

    func deleteCurrentUser() async throws {
        guard let user = auth.currentUser else {
            return
        }
        do {
            try await user.delete()
        } catch {
            let nsError = error as NSError
            guard nsError.domain == AuthErrorDomain,
                  nsError.code == AuthErrorCode.userNotFound.rawValue else {
                throw error
            }
        }
        try? auth.signOut()
    }
}

final class UserRepository {
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west1")
    private let transferService = VideoTransferService()

    private var users: CollectionReference { db.collection("users") }


    private var pseudos: CollectionReference { db.collection("pseudos") }

    private var communities: CollectionReference { db.collection("communities") }


    private func doubleValue(from rawValue: Any?) -> Double? {
        if let value = rawValue as? Double { return value }
        if let value = rawValue as? NSNumber { return value.doubleValue }
        return nil
    }

    private func timestampValue(from rawValue: Any?) -> Timestamp? {
        rawValue as? Timestamp
    }


    private func decodeUserProfile(from snapshot: DocumentSnapshot, fallbackUID: String) -> UserProfile {
        let data = snapshot.data() ?? [:]
        return UserProfile(
            documentId: snapshot.documentID,
            uid: (data["uid"] as? String) ?? fallbackUID,
            email: (data["email"] as? String) ?? auth.currentUser?.email,
            firstName: (data["firstName"] as? String) ?? "",
            lastName: (data["lastName"] as? String) ?? "",
            pseudo: (data["pseudo"] as? String) ?? "",
            pseudoKey: (data["pseudoKey"] as? String) ?? "",
            photoUrl: data["photoUrl"] as? String,
            profileIcon: data["profileIcon"] as? String,
            communityIds: CommunityMembershipStore.normalizedIDs(from: data["communityIds"]),
            pinnedCommunityIds: CommunityMembershipStore.normalizedIDs(from: data["pinnedCommunityIds"], limit: 3),
            communityXP: extractCommunityXP(from: data),
            xpTotal: extractTotalXP(from: data),
            fcmToken: (data["fcmTokens"] as? [String])?.first ?? (data["fcmToken"] as? String),
            languageCode: data["languageCode"] as? String,
            isLanguagePublic: (data["isLanguagePublic"] as? Bool) ?? true,
            isLeaderboardPublic: (data["isLeaderboardPublic"] as? Bool) ?? true,
            isGhostMode: (data["isGhostMode"] as? Bool) ?? false,
            friendsCount: (data["friendsCount"] as? Int) ?? (data["friendsCount"] as? NSNumber)?.intValue ?? 0,
            birthDate: timestampValue(from: data["birthDate"]),
            sex: (data["sex"] as? String).flatMap(ProfileSex.init(rawValue:)),
            city: data["city"] as? String,
            bio: data["bio"] as? String,
            lastLatitude: doubleValue(from: data["lastLatitude"]),
            lastLongitude: doubleValue(from: data["lastLongitude"]),
            lastLocationUpdatedAt: timestampValue(from: data["lastLocationUpdatedAt"]),
            termsAcceptedAt: data["termsAcceptedAt"] as? Timestamp,
            moderationRulesAcceptedAt: data["moderationRulesAcceptedAt"] as? Timestamp,
            updatedAt: data["updatedAt"] as? Timestamp
        )
    }

    private func commitDeleteChunks(for references: [DocumentReference], chunkSize: Int = 400) async throws {
        guard !references.isEmpty else { return }

        var startIndex = 0
        while startIndex < references.count {
            let endIndex = min(startIndex + chunkSize, references.count)
            let batch = db.batch()
            for reference in references[startIndex..<endIndex] {
                batch.deleteDocument(reference)
            }
            try await batch.commit()
            startIndex = endIndex
        }
    }

    private func deleteCollection(_ collection: CollectionReference) async throws {
        let snapshot = try await collection.getDocuments()
        let references = snapshot.documents.map(\.reference)
        try await commitDeleteChunks(for: references)
    }

    private func deleteCommunityTree(_ communityReference: DocumentReference) async throws {
        try await deleteCollection(communityReference.collection("messages"))
        try await deleteCollection(communityReference.collection("torpilles"))
        try await deleteCollection(communityReference.collection("savedMessages"))
        try await deleteCollection(communityReference.collection("allowlist"))
        try await deleteCollection(communityReference.collection("banned"))
        try await deleteCollection(communityReference.collection("members"))
        try await communityReference.delete()
    }

    private func deleteProfileImageIfNeeded(photoURL: String?, preservingPath: String? = nil) async {
        guard let photoURL, !photoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            let reference = Storage.storage().reference(forURL: photoURL)
            guard reference.fullPath != preservingPath else { return }
            try await reference.delete()
        } catch {
            debugLog("UserRepository.deleteProfileImageIfNeeded failed", error)
        }
    }

    private func selectReplacementAdmin(
        in members: [Member],
        excluding uid: String
    ) -> Member? {
        members
            .filter { $0.uid != uid && !$0.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.xpInCommunity != rhs.xpInCommunity {
                    return lhs.xpInCommunity > rhs.xpInCommunity
                }

                let leftName = lhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let rightName = rhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let nameOrder = leftName.localizedCaseInsensitiveCompare(rightName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }

                return lhs.uid.localizedCaseInsensitiveCompare(rhs.uid) == .orderedAscending
            }
            .first
    }

    func getMeOrThrow() async throws -> UserProfile {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        do {
            let snapshot = try await users.document(uid).getDocument()
            guard snapshot.exists else {
                throw TorpilleError.missingData("Ton profil n’est pas encore configuré. Complète les informations obligatoires et accepte l’EULA pour continuer.")
            }
            return decodeUserProfile(from: snapshot, fallbackUID: uid)
        } catch {
            debugLog("UserRepository.getMeOrThrow failed", error)
            throw error
        }
    }

    func observeMe(handler: @escaping (UserProfile?) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler(nil)
            return nil
        }

        return users.document(uid).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists else {
                handler(nil)
                return
            }
            handler(self.decodeUserProfile(from: snapshot, fallbackUID: uid))
        }
    }

    func observeGlobalLeaderboard(limit: Int = 0, handler: @escaping ([UserProfile]) -> Void) -> ListenerRegistration {
        users.addSnapshotListener { [weak self] snapshot, _ in
            guard let self else {
                handler([])
                return
            }

            let sortedValues = (snapshot?.documents.map { document in
                self.decodeUserProfile(from: document, fallbackUID: document.documentID)
            } ?? [])
            .sorted { lhs, rhs in
                if lhs.effectiveTotalXP != rhs.effectiveTotalXP {
                    return lhs.effectiveTotalXP > rhs.effectiveTotalXP
                }

                let leftName = lhs.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
                let rightName = rhs.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
                let nameOrder = leftName.localizedCaseInsensitiveCompare(rightName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.uid.localizedCaseInsensitiveCompare(rhs.uid) == .orderedAscending
            }

            if limit > 0 {
                handler(Array(sortedValues.prefix(limit)))
            } else {
                handler(sortedValues)
            }
        }
    }

    func upsertProfile(firstName: String, lastName: String, pseudo: String, birthDate: Date?, sex: ProfileSex?, city: String, bio: String, photoURL: String?, profileIcon: String?, acceptsTerms: Bool) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        print("📍 UserRepository.upsertProfile")
        print("👤 uid =", uid)
        print("👤 pseudo =", pseudo)
        print("👤 photoURL =", photoURL ?? "nil")
        print("👤 profileIcon =", profileIcon ?? "nil")

        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...50).contains(cleanFirstName.count), (2...50).contains(cleanLastName.count) else {
            throw TorpilleError.missingData("Renseigne un prénom et un nom valides pour compléter ton profil.")
        }
        guard cleanCity.count <= 100, cleanBio.count <= 300 else {
            throw TorpilleError.missingData("La ville est limitée à 100 caractères et la présentation à 300 caractères.")
        }
        if let birthDate, birthDate > Date() {
            throw TorpilleError.missingData("La date de naissance ne peut pas être dans le futur.")
        }
        try BasicContentFilter.validate([cleanFirstName, cleanLastName, cleanCity, cleanBio].joined(separator: " "))

        let clean = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        try BasicContentFilter.validate(clean)
        guard clean.count >= 3,
              clean.count <= 20,
              clean.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else {
            throw TorpilleError.invalidPseudo
        }

        let pseudoKey = clean.normalizedPseudoKey
        let userRef = users.document(uid)
        let currentEmail = auth.currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Timestamp(date: Date())

        let userSnapshot = try await userRef.getDocument()
        let existingData = userSnapshot.data() ?? [:]
        let currentKey = existingData["pseudoKey"] as? String ?? ""
        let existingPhotoURL = existingData["photoUrl"] as? String
        let existingProfileIcon = existingData["profileIcon"] as? String

        let resolvedPhotoURL = photoURL?.isEmpty == false ? photoURL : existingPhotoURL

        let resolvedProfileIcon: String?
        if photoURL?.isEmpty == false {
            resolvedProfileIcon = nil
        } else {
            resolvedProfileIcon = profileIcon?.isEmpty == false ? profileIcon : existingProfileIcon
        }

        let existingXPTotal = extractTotalXP(from: existingData)
        let existingCommunityXP = extractCommunityXP(from: existingData)
        let alreadyAcceptedTerms = existingData["termsAcceptedAt"] as? Timestamp
        let alreadyAcceptedRules = existingData["moderationRulesAcceptedAt"] as? Timestamp
        let hasAvatar = resolvedPhotoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || resolvedProfileIcon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        guard hasAvatar else {
            throw TorpilleError.missingData("Ajoute une photo ou une icône de profil pour éviter les profils anonymes.")
        }

        var payload: [String: Any] = [
            "uid": uid,
            "firstName": cleanFirstName,
            "lastName": cleanLastName,
            "pseudo": clean,
            "pseudoKey": pseudoKey,
            "communityIds": CommunityMembershipStore.normalizedIDs(from: existingData["communityIds"]),
            "communityXP": existingCommunityXP,
            "xptotal": existingXPTotal,
            "xpTotal": existingXPTotal,
            "isLanguagePublic": existingData["isLanguagePublic"] as? Bool ?? true,
            "isLeaderboardPublic": existingData["isLeaderboardPublic"] as? Bool ?? true,
            "updatedAt": now
        ]

        if let birthDate {
            payload["birthDate"] = Timestamp(date: birthDate)
        } else if let existingBirthDate = existingData["birthDate"] as? Timestamp {
            payload["birthDate"] = existingBirthDate
        }
        payload["sex"] = sex.map { $0.rawValue as Any } ?? NSNull()
        payload["city"] = cleanCity
        payload["bio"] = cleanBio

        if let alreadyAcceptedTerms {
            payload["termsAcceptedAt"] = alreadyAcceptedTerms
        } else if acceptsTerms {
            payload["termsAcceptedAt"] = now
        }

        if let alreadyAcceptedRules {
            payload["moderationRulesAcceptedAt"] = alreadyAcceptedRules
        } else if acceptsTerms {
            payload["moderationRulesAcceptedAt"] = now
        }

        if let currentEmail, !currentEmail.isEmpty {
            payload["email"] = currentEmail
        }

        if let resolvedPhotoURL, !resolvedPhotoURL.isEmpty {
            payload["photoUrl"] = resolvedPhotoURL
        } else {
            payload["photoUrl"] = FieldValue.delete()
        }

        if let resolvedProfileIcon, !resolvedProfileIcon.isEmpty {
            payload["profileIcon"] = resolvedProfileIcon
        } else {
            payload["profileIcon"] = FieldValue.delete()
        }

        let pseudoRef = pseudos.document(pseudoKey)

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let pseudoSnapshot = try transaction.getDocument(pseudoRef)

                    if pseudoSnapshot.exists,
                       let owner = pseudoSnapshot.data()?["uid"] as? String,
                       owner != uid {
                        let error = NSError(
                            domain: "UserRepository",
                            code: 409,
                            userInfo: [NSLocalizedDescriptionKey: TorpilleError.pseudoAlreadyUsed.localizedDescription]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }

                    if !pseudoSnapshot.exists {
                        transaction.setData(
                            [
                                "uid": uid,
                                "createdAt": now
                            ],
                            forDocument: pseudoRef
                        )
                    }

                    transaction.setData(payload, forDocument: userRef, merge: true)
                    if !currentKey.isEmpty && currentKey != pseudoKey {
                        transaction.deleteDocument(self.pseudos.document(currentKey))
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            debugLog("UserRepository.upsertProfile transaction failed", error)
            let nsError = error as NSError
            if nsError.domain == "UserRepository" && nsError.code == 409 {
                throw TorpilleError.pseudoAlreadyUsed
            }
            throw error
        }
    }

    private func ensurePseudoIsAvailable(_ pseudo: String) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        let clean = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3,
              clean.count <= 20,
              clean.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else {
            throw TorpilleError.invalidPseudo
        }

        let reservation = try await pseudos.document(clean.normalizedPseudoKey).getDocument()
        if reservation.exists,
           let owner = reservation.data()?["uid"] as? String,
           owner != uid {
            throw TorpilleError.pseudoAlreadyUsed
        }
    }

    func updateProfile(firstName: String, lastName: String, pseudo: String, birthDate: Date?, sex: ProfileSex?, city: String, bio: String, imageData: Data?, profileIcon: String?, acceptsTerms: Bool = false) async throws {
        print("📍 UserRepository.updateProfile")
        print("👤 auth uid =", auth.currentUser?.uid ?? "nil")
        print("👤 auth email =", auth.currentUser?.email ?? "nil")
        print("👤 pseudo =", pseudo)
        print("👤 has imageData =", imageData != nil)
        print("👤 profileIcon =", profileIcon ?? "nil")

        try await ensurePseudoIsAvailable(pseudo)

        let uid = auth.currentUser?.uid
        let previousPhotoURL: String?
        if let uid {
            previousPhotoURL = try? await users.document(uid).getDocument().data()?["photoUrl"] as? String
        } else {
            previousPhotoURL = nil
        }

        var uploadedImage: UploadedImage?

        if let imageData, let uid {
            print("🖼 image byteCount =", imageData.count)
            let compressed = normalizedProfileImageData(from: imageData) ?? imageData
            do {
                let uploaded = try await transferService.uploadProfileImage(
                    uid: uid,
                    imageData: compressed
                )
                uploadedImage = uploaded
                print("✅ uploadProfileImage ok bucket = \(uploaded.bucket) path = \(uploaded.storagePath)")
            } catch {
                debugLog("UserRepository.updateProfile uploadProfileImage failed", error)
                throw error
            }
        }

        do {
            try await upsertProfile(firstName: firstName, lastName: lastName, pseudo: pseudo, birthDate: birthDate, sex: sex, city: city, bio: bio, photoURL: uploadedImage?.downloadURL, profileIcon: profileIcon, acceptsTerms: acceptsTerms)
            print("✅ upsertProfile ok")
        } catch {
            debugLog("UserRepository.updateProfile upsertProfile failed", error)
            throw error
        }

        // Once Firestore points to the new avatar (or to a profile icon), the
        // formerly referenced timestamped object is no longer needed.
        if uploadedImage != nil || (profileIcon?.isEmpty == false && imageData == nil) {
            await deleteProfileImageIfNeeded(
                photoURL: previousPhotoURL,
                preservingPath: uploadedImage?.storagePath
            )
        }

        do {
            try await propagateProfileToCommunityMemberships(
                pseudo: pseudo,
                photoURL: uploadedImage?.downloadURL,
                profileIcon: profileIcon
            )
            print("✅ propagateProfileToCommunityMemberships ok")
        } catch {
            debugLog("UserRepository.updateProfile propagateProfileToCommunityMemberships failed", error)
        }
    }

    func updatePinnedCommunities(_ communityIds: [String]) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        let cleaned = CommunityMembershipStore.normalizedIDs(from: communityIds, limit: 3)

        try await users.document(uid).setData([
            "pinnedCommunityIds": cleaned,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    func setCommunityIds(_ communityIds: [String]) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        let cleaned = CommunityMembershipStore.normalizedIDs(from: communityIds)
        try await users.document(uid).setData([
            "communityIds": cleaned,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    func registerFCMToken(_ token: String, for uid: String? = nil) async throws {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        let resolvedUID = uid ?? auth.currentUser?.uid
        guard let resolvedUID, !resolvedUID.isEmpty else {
            throw TorpilleError.notAuthenticated
        }

        try await users.document(resolvedUID).setData([
            "fcmToken": cleanToken,
            "fcmTokens": FieldValue.arrayUnion([cleanToken]),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    func unregisterFCMToken(_ token: String, for uid: String? = nil) async throws {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        let resolvedUID = uid ?? auth.currentUser?.uid
        guard let resolvedUID, !resolvedUID.isEmpty else {
            throw TorpilleError.notAuthenticated
        }

        let userRef = users.document(resolvedUID)
        let snapshot = try await userRef.getDocument()
        let currentPrimaryToken = snapshot.data()?["fcmToken"] as? String

        var payload: [String: Any] = [
            "fcmTokens": FieldValue.arrayRemove([cleanToken]),
            "updatedAt": Timestamp(date: Date())
        ]
        if currentPrimaryToken == cleanToken {
            payload["fcmToken"] = FieldValue.delete()
        }

        try await userRef.setData(payload, merge: true)
    }

    func updatePublicProfileSettings(languageCode: String?, isLanguagePublic: Bool, isLeaderboardPublic: Bool) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        var payload: [String: Any] = [
            "isLanguagePublic": isLanguagePublic,
            "isLeaderboardPublic": isLeaderboardPublic,
            "updatedAt": Timestamp(date: Date())
        ]
        if let languageCode, !languageCode.isEmpty {
            payload["languageCode"] = languageCode
        }
        try await users.document(uid).setData(payload, merge: true)
    }

    func searchUsersByPseudo(_ query: String, limit: Int = 20) async throws -> [UserProfile] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).normalizedPseudoKey
        guard clean.count >= 2 else { return [] }
        let snapshot = try await users
            .whereField("pseudoKey", isGreaterThanOrEqualTo: clean)
            .whereField("pseudoKey", isLessThanOrEqualTo: clean + "\u{f8ff}")
            .limit(to: limit)
            .getDocuments()

        let myUID = auth.currentUser?.uid ?? ""
        let profiles = snapshot.documents
            .map { decodeUserProfile(from: $0, fallbackUID: $0.documentID) }
            .filter { $0.uid != myUID }
        return await enrichProfilesWithFriendCounts(profiles)
    }

    private func enrichProfilesWithFriendCounts(_ profiles: [UserProfile]) async -> [UserProfile] {
        await withTaskGroup(of: (String, Int).self) { group in
            for profile in profiles where !profile.uid.isEmpty {
                group.addTask {
                    let snapshot = try? await self.users.document(profile.uid).collection("friends").getDocuments()
                    return (profile.uid, snapshot?.documents.count ?? 0)
                }
            }

            var counts: [String: Int] = [:]
            for await pair in group {
                counts[pair.0] = pair.1
            }

            return profiles.map { profile in
                var enriched = profile
                enriched.friendsCount = counts[profile.uid] ?? profile.friendsCount
                return enriched
            }
        }
    }

    func observeFriends(handler: @escaping ([PublicFriend]) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else { return nil }
        return users.document(uid).collection("friends")
            .order(by: "pseudo")
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: PublicFriend.self) } ?? []
                handler(values)
            }
    }

    func removeFriend(_ friend: PublicFriend) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard !friend.uid.isEmpty, friend.uid != uid else {
            throw TorpilleError.missingData("Cet ami ne peut pas être supprimé.")
        }

        let me = try await getMeOrThrow()
        let batch = db.batch()
        batch.deleteDocument(users.document(uid).collection("friends").document(friend.uid))
        batch.deleteDocument(users.document(friend.uid).collection("friends").document(uid))

        let removalReference = db.collection("friendRemovals").document()
        batch.setData([
            "actorUid": uid,
            "actorPseudo": me.pseudo,
            "toUid": friend.uid,
            "type": "friendRemoved",
            "createdAt": Timestamp(date: Date())
        ], forDocument: removalReference)

        try await batch.commit()
    }

    func sendFriendRequest(to profile: UserProfile) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard profile.uid != uid else { throw TorpilleError.missingData("Tu ne peux pas t'ajouter toi-même.") }

        let friendDocument = try await users.document(uid).collection("friends").document(profile.uid).getDocument()
        guard !friendDocument.exists else {
            throw TorpilleError.missingData("@\(profile.pseudo) fait déjà partie de tes amis.")
        }

        let me = try await getMeOrThrow()
        let requestId = [uid, profile.uid].sorted().joined(separator: "_")
        let requestReference = db.collection("friendRequests").document(requestId)
        let existingRequest = try await requestReference.getDocument()
        if let data = existingRequest.data() {
            let status = data["status"] as? String ?? ""
            let existingFromUid = data["fromUid"] as? String ?? ""
            if status == FriendRequestStatus.pending.rawValue {
                if existingFromUid == uid {
                    throw TorpilleError.missingData("Une demande d'ami est déjà en attente pour @\(profile.pseudo).")
                }
                throw TorpilleError.missingData("@\(profile.pseudo) t'a déjà envoyé une demande. Ouvre tes notifications pour l'accepter.")
            }
            if existingFromUid == uid {
                try await requestReference.delete()
            } else {
                throw TorpilleError.missingData("Cette ancienne demande doit être supprimée par @\(profile.pseudo) avant un nouvel envoi.")
            }
        }

        try await requestReference.setData([
            "fromUid": uid,
            "fromPseudo": me.pseudo,
            "fromPhotoUrl": me.photoUrl ?? "",
            "fromProfileIcon": me.profileIcon ?? "",
            "toUid": profile.uid,
            "toPseudo": profile.pseudo,
            "status": FriendRequestStatus.pending.rawValue,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], merge: false)
    }

    func acceptFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = auth.currentUser?.uid, request.toUid == uid else {
            throw TorpilleError.notAuthenticated
        }
        let me = try await getMeOrThrow()
        let now = Timestamp(date: Date())
        let batch = db.batch()
        let requestRef = db.collection("friendRequests").document(request.id)
        batch.setData([
            "status": FriendRequestStatus.accepted.rawValue,
            "updatedAt": now
        ], forDocument: requestRef, merge: true)
        batch.setData([
            "uid": request.fromUid,
            "pseudo": request.fromPseudo,
            "photoUrl": request.fromPhotoUrl ?? "",
            "profileIcon": request.fromProfileIcon ?? "",
            "createdAt": now
        ], forDocument: users.document(uid).collection("friends").document(request.fromUid), merge: true)
        batch.setData([
            "uid": uid,
            "pseudo": me.pseudo,
            "photoUrl": me.photoUrl ?? "",
            "profileIcon": me.profileIcon ?? "",
            "createdAt": now
        ], forDocument: users.document(request.fromUid).collection("friends").document(uid), merge: true)
        try await batch.commit()
    }

    func rejectFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = auth.currentUser?.uid, request.toUid == uid else {
            throw TorpilleError.notAuthenticated
        }
        try await db.collection("friendRequests").document(request.id).setData([
            "status": FriendRequestStatus.rejected.rawValue,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    private func propagateProfileToCommunityMemberships(pseudo: String, photoURL: String?, profileIcon: String?) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        let cleanPseudo = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)

        let membershipSnapshot = try await db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()

        for document in membershipSnapshot.documents {
            var payload: [String: Any] = [
                "pseudo": cleanPseudo
            ]

            if let photoURL, !photoURL.isEmpty {
                payload["photoUrl"] = photoURL
                payload["profileIcon"] = FieldValue.delete()
            } else if let profileIcon, !profileIcon.isEmpty {
                payload["profileIcon"] = profileIcon
                payload["photoUrl"] = FieldValue.delete()
            }

            try await document.reference.setData(payload, merge: true)
        }
    }

    func deleteCurrentAccountData() async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        let userRef = users.document(uid)
        let userSnapshot = try await userRef.getDocument()
        let userData = userSnapshot.data() ?? [:]
        let pseudoKey = userData["pseudoKey"] as? String
        let photoURL = userData["photoUrl"] as? String

        let ownedCommunities = try await communities
            .whereField("adminUid", isEqualTo: uid)
            .getDocuments()

        for communityDocument in ownedCommunities.documents {
            let communityRef = communityDocument.reference
            let membersSnapshot = try await communityRef.collection("members").getDocuments()
            let members = membersSnapshot.documents.compactMap { try? $0.data(as: Member.self) }

            if let replacementAdmin = selectReplacementAdmin(in: members, excluding: uid) {
                try await communityRef.updateData([
                    "adminUid": replacementAdmin.uid
                ])
            } else {
                try await deleteCommunityTree(communityRef)
            }
        }

        let memberships = try await db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()
        try await commitDeleteChunks(for: memberships.documents.map(\.reference))

        let notificationPreferences = try await userRef.collection("notificationPreferences").getDocuments()
        try await commitDeleteChunks(for: notificationPreferences.documents.map(\.reference))

        await deleteProfileImageIfNeeded(photoURL: photoURL)

        if let pseudoKey, !pseudoKey.isEmpty {
            do {
                try await pseudos.document(pseudoKey).delete()
            } catch {
                debugLog("UserRepository.deleteCurrentAccountData pseudo delete failed", error)
            }
        }

        if userSnapshot.exists {
            try await userRef.delete()
        }
    }

    func deleteCurrentAccountServerSide() async throws {
        _ = try await functions.httpsCallable("deleteMyAccount").call()
    }
}

final class CommunityRepository {
    private let auth = Auth.auth()
    var currentUID: String { auth.currentUser?.uid ?? "" }
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west1")
    private let videoTransfer = VideoTransferService()
    private var messageRetentionInterval: TimeInterval { 14 * 24 * 60 * 60 }
    private var torpilleRetentionInterval: TimeInterval { 14 * 24 * 60 * 60 }

    private var communities: CollectionReference { db.collection("communities") }
    private var users: CollectionReference { db.collection("users") }
    private var reels: CollectionReference { db.collection("reels") }
    private var reports: CollectionReference { db.collection("reports") }

    private func normalizedCommunityIds(_ communityIds: [String]) -> [String] {
        CommunityMembershipStore.normalizedIDs(from: communityIds)
    }

    private func loadProfileCommunityIds(for uid: String) async throws -> [String] {
        let snapshot = try await users.document(uid).getDocument()
        return CommunityMembershipStore.normalizedIDs(from: snapshot.data()?["communityIds"])
    }

    private func loadBlockedUserIds() async -> Set<String> {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try? await users.document(uid).collection("blockedUsers").getDocuments()
        return Set(snapshot?.documents.map(\.documentID) ?? [])
    }

    private func observeBlockedByUserIds(handler: @escaping (Set<String>) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler([])
            return nil
        }

        functions.httpsCallable("syncBlockedByForMe").call { _, error in
            if let error { debugLog("CommunityRepository.syncBlockedByForMe failed", error) }
        }

        return users.document(uid)
            .collection("blockedBy")
            .addSnapshotListener { snapshot, _ in
                handler(Set(snapshot?.documents.map(\.documentID) ?? []))
            }
    }

    private func loadHiddenMemberIds(communityId: String) async -> Set<String> {
        guard let uid = auth.currentUser?.uid else { return [] }
        let snapshot = try? await users.document(uid)
            .collection("contentFilters")
            .document(communityId)
            .collection("hiddenMembers")
            .getDocuments()
        return Set(snapshot?.documents.map(\.documentID) ?? [])
    }

    func observeHiddenMemberIds(communityId: String, handler: @escaping (Set<String>) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler([])
            return nil
        }

        return users.document(uid)
            .collection("contentFilters")
            .document(communityId)
            .collection("hiddenMembers")
            .addSnapshotListener { snapshot, _ in
                handler(Set(snapshot?.documents.map(\.documentID) ?? []))
            }
    }

    private func loadExcludedUserIds(communityId: String?) async -> Set<String> {
        var excluded = await loadBlockedUserIds()
        if let communityId, !communityId.isEmpty {
            excluded.formUnion(await loadHiddenMemberIds(communityId: communityId))
        }
        return excluded
    }

    private func observeExcludedUserIds(communityId: String?, handler: @escaping (Set<String>) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler([])
            return nil
        }

        var blockedIds: Set<String> = []
        var blockedByIds: Set<String> = []
        var hiddenIds: Set<String> = []
        var hasLoadedBlocked = false
        var hasLoadedBlockedBy = false
        var hasLoadedHidden = communityId?.isEmpty == false ? false : true

        func publish() {
            guard hasLoadedBlocked, hasLoadedBlockedBy, hasLoadedHidden else { return }
            var excluded = blockedIds
            excluded.formUnion(blockedByIds)
            excluded.formUnion(hiddenIds)
            handler(excluded)
        }

        var registrations: [ListenerRegistration] = []
        let blockedRegistration = users.document(uid)
            .collection("blockedUsers")
            .addSnapshotListener { snapshot, _ in
                hasLoadedBlocked = true
                blockedIds = Set(snapshot?.documents.map(\.documentID) ?? [])
                publish()
            }
        registrations.append(blockedRegistration)

        if let blockedByRegistration = observeBlockedByUserIds(handler: { ids in
            hasLoadedBlockedBy = true
            blockedByIds = ids
            publish()
        }) {
            registrations.append(blockedByRegistration)
        } else {
            hasLoadedBlockedBy = true
        }

        if let communityId, !communityId.isEmpty {
            let hiddenRegistration = users.document(uid)
                .collection("contentFilters")
                .document(communityId)
                .collection("hiddenMembers")
                .addSnapshotListener { snapshot, _ in
                    hasLoadedHidden = true
                    hiddenIds = Set(snapshot?.documents.map(\.documentID) ?? [])
                    publish()
                }
            registrations.append(hiddenRegistration)
        }

        return CompositeListenerRegistration(registrations)
    }

    private func filterMembers(_ members: [Member], excluded: Set<String>) -> [Member] {
        members.filter { member in
            member.uid == auth.currentUser?.uid || excluded.contains(member.uid) == false
        }
    }

    private func filterMembers(_ members: [Member], communityId: String) async -> [Member] {
        let excluded = await loadExcludedUserIds(communityId: communityId)
        return filterMembers(members, excluded: excluded)
    }

    private func filterMessages(_ messages: [Message], excluded: Set<String>) -> [Message] {
        messages.filter { message in
            !message.isQuarantined && excluded.contains(message.senderUid) == false
        }
    }

    private func filterMessages(_ messages: [Message], communityId: String) async -> [Message] {
        let excluded = await loadExcludedUserIds(communityId: communityId)
        return filterMessages(messages, excluded: excluded)
    }

    private func filterTorpilles(_ torpilles: [Torpille], excluded: Set<String>) -> [Torpille] {
        let oldestVisibleDate = Date().addingTimeInterval(-torpilleRetentionInterval)
        return torpilles.filter { torpille in
            let createdAt = torpille.createdAt?.dateValue() ?? .distantPast
            return !torpille.isQuarantined
                && excluded.contains(torpille.fromUid) == false
                && createdAt >= oldestVisibleDate
        }
    }

    private func filterTorpilles(_ torpilles: [Torpille], communityId: String) async -> [Torpille] {
        let excluded = await loadExcludedUserIds(communityId: communityId)
        return filterTorpilles(torpilles, excluded: excluded)
    }

    private func filterReels(_ reels: [PublishedReel]) async -> [PublishedReel] {
        let excluded = await loadBlockedUserIds()
        return filterReels(reels, blockedUserIds: excluded)
    }

    private func filterReels(_ reels: [PublishedReel], blockedUserIds: Set<String>) -> [PublishedReel] {
        return reels.filter { reel in
            !reel.isQuarantined && blockedUserIds.contains(reel.authorUid) == false
        }
    }

    private func enrichReelsWithAuthorProfiles(_ reels: [PublishedReel]) async -> [PublishedReel] {
        let authorIds = Array(Set(reels.map(\.authorUid).filter { !$0.isEmpty }))
        guard !authorIds.isEmpty else { return reels }

        let profilesByUID = await withTaskGroup(of: (String, UserProfile?).self) { group in
            for uid in authorIds {
                group.addTask {
                    let snapshot = try? await self.users.document(uid).getDocument()
                    let profile = snapshot.flatMap { document -> UserProfile? in
                        guard document.exists else { return nil }
                        var profile = try? document.data(as: UserProfile.self)
                        if profile?.uid.isEmpty == true {
                            profile?.uid = uid
                        }
                        return profile
                    }
                    return (uid, profile)
                }
            }

            var collected: [(String, UserProfile?)] = []
            for await pair in group {
                collected.append(pair)
            }
            return Dictionary(uniqueKeysWithValues: collected.compactMap { uid, profile in
                profile.map { (uid, $0) }
            })
        }

        return reels.map { reel in
            guard let profile = profilesByUID[reel.authorUid] else {
                return reel
            }

            var enriched = reel
            if !profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                enriched.authorPseudo = profile.pseudo
            }
            enriched.authorPhotoUrl = profile.photoUrl
            enriched.authorProfileIcon = profile.profileIcon
            return enriched
        }
    }

    private func setProfileCommunityIds(_ communityIds: [String], for uid: String) async throws {
        try await users.document(uid).setData([
            "communityIds": normalizedCommunityIds(communityIds),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    private func appendCommunityIdToProfile(_ communityId: String, for uid: String) async throws {
        let cleanCommunityId = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCommunityId.isEmpty else { return }
        try await users.document(uid).setData([
            "communityIds": FieldValue.arrayUnion([cleanCommunityId]),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    private func removeCommunityIdsFromProfile(_ communityIds: [String], for uid: String) async throws {
        let cleaned = Set(normalizedCommunityIds(communityIds))
        guard !cleaned.isEmpty else { return }
        let current = try await loadProfileCommunityIds(for: uid)
        let updated = current.filter { cleaned.contains($0) == false }
        if updated != current {
            try await setProfileCommunityIds(updated, for: uid)
        }
    }

    private func fallbackMembershipCommunityIds(for uid: String) async throws -> [String] {
        let snapshot = try await db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()

        let ids = snapshot.documents.compactMap { $0.reference.parent.parent?.documentID }
        let cleaned = normalizedCommunityIds(ids)
        try await setProfileCommunityIds(cleaned, for: uid)
        return cleaned
    }

    private func loadMembershipCommunityIds(for uid: String) async throws -> [String] {
        let snapshot = try await db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()
        return normalizedCommunityIds(snapshot.documents.compactMap { $0.reference.parent.parent?.documentID })
    }

    private func loadCanonicalCommunityIds(for uid: String) async throws -> [String] {
        let profileCommunityIds = try await loadProfileCommunityIds(for: uid)
        if profileCommunityIds.isEmpty {
            return try await fallbackMembershipCommunityIds(for: uid)
        }
        return profileCommunityIds
    }

    private func resolveCommunities(for uid: String, communityIds: [String], onPartial: (([Community]) -> Void)? = nil) async -> (communities: [Community], validIds: [String]) {
        var result: [(Community, Member)] = []
        var validCommunityIds: [String] = []

        await withTaskGroup(of: (String, Community, Member)?.self) { group in
            for communityId in communityIds {
                group.addTask {
                    let communityRef = self.communities.document(communityId)
                    async let communitySnapshot = communityRef.getDocument()
                    async let memberSnapshot = communityRef.collection("members").document(uid).getDocument()
                    guard let resolvedCommunity = try? await communitySnapshot,
                          resolvedCommunity.exists,
                          let community = self.decodeCommunity(from: resolvedCommunity),
                          let resolvedMember = try? await memberSnapshot,
                          resolvedMember.exists,
                          let member = self.decodeMember(from: resolvedMember) else { return nil }
                    return (communityId, community, member)
                }
            }
            for await value in group {
                guard let (id, community, member) = value else { continue }
                validCommunityIds.append(id)
                result.append((community, member))
                onPartial?(result.map(\.0))
            }
        }

        let sorted = result.sorted { lhs, rhs in
            let lhsOpenedAt = lhs.1.lastOpenedAt?.dateValue() ?? .distantPast
            let rhsOpenedAt = rhs.1.lastOpenedAt?.dateValue() ?? .distantPast
            if lhsOpenedAt != rhsOpenedAt {
                return lhsOpenedAt > rhsOpenedAt
            }

            let lhsCreatedAt = lhs.0.createdAt?.dateValue() ?? .distantPast
            let rhsCreatedAt = rhs.0.createdAt?.dateValue() ?? .distantPast
            if lhsCreatedAt != rhsCreatedAt {
                return lhsCreatedAt > rhsCreatedAt
            }

            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }.map(\.0)

        return (sorted, communityIds.filter { validCommunityIds.contains($0) })
    }

    private func ensureMemberDocumentExists(
        communityId: String,
        uid: String,
        fallbackPseudo: String
    ) async throws {
        let cleanUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUID.isEmpty else {
            throw TorpilleError.missingData("Membre de communaute introuvable.")
        }

        let memberRef = communities.document(communityId).collection("members").document(cleanUID)
        let memberSnapshot = try await memberRef.getDocument()
        guard !memberSnapshot.exists else { return }

        let userSnapshot = try await users.document(cleanUID).getDocument()
        let userData = userSnapshot.data() ?? [:]
        let pseudoFromProfile = ((userData["pseudo"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFallbackPseudo = fallbackPseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPseudo = pseudoFromProfile.isEmpty ? cleanFallbackPseudo : pseudoFromProfile

        guard !resolvedPseudo.isEmpty else {
            throw TorpilleError.missingData("Pseudo introuvable pour preparer cette torpille.")
        }

        var payload: [String: Any] = [
            "uid": cleanUID,
            "pseudo": resolvedPseudo,
            "xpInCommunity": Int64(0)
        ]

        if let photoUrl = userData["photoUrl"] as? String, !photoUrl.isEmpty {
            payload["photoUrl"] = photoUrl
        }
        if let profileIcon = userData["profileIcon"] as? String, !profileIcon.isEmpty {
            payload["profileIcon"] = profileIcon
        }

        try await memberRef.setData(payload, merge: false)
    }

    private func commitDeleteChunks(for references: [DocumentReference], chunkSize: Int = 400) async throws {
        guard !references.isEmpty else { return }

        var startIndex = 0
        while startIndex < references.count {
            let endIndex = min(startIndex + chunkSize, references.count)
            let batch = db.batch()
            for reference in references[startIndex..<endIndex] {
                batch.deleteDocument(reference)
            }
            try await batch.commit()
            startIndex = endIndex
        }
    }

    private func stringValue(from rawValue: Any?) -> String? {
        guard let value = rawValue as? String else { return nil }
        return value
    }

    private func doubleValue(from rawValue: Any?) -> Double? {
        if let value = rawValue as? Double { return value }
        if let value = rawValue as? Int { return Double(value) }
        if let value = rawValue as? Int64 { return Double(value) }
        if let value = rawValue as? NSNumber { return value.doubleValue }
        return nil
    }

    private func timestampValue(from rawValue: Any?) -> Timestamp? {
        rawValue as? Timestamp
    }

    private func int64Value(from rawValue: Any?) -> Int64 {
        if let value = rawValue as? Int64 { return value }
        if let value = rawValue as? Int { return Int64(value) }
        if let value = rawValue as? Double { return Int64(value) }
        if let value = rawValue as? NSNumber { return value.int64Value }
        return 0
    }

    private func boolValue(from rawValue: Any?, default defaultValue: Bool = false) -> Bool {
        if let value = rawValue as? Bool { return value }
        if let value = rawValue as? NSNumber { return value.boolValue }
        return defaultValue
    }

    private func decodeCommunity(from snapshot: DocumentSnapshot) -> Community? {
        let data = snapshot.data() ?? [:]
        return Community(
            documentId: snapshot.documentID,
            id: (data["id"] as? String) ?? snapshot.documentID,
            name: (data["name"] as? String) ?? "",
            isPublic: boolValue(from: data["isPublic"], default: true),
            adminUid: (data["adminUid"] as? String) ?? "",
            responseTimeSeconds: int64Value(from: data["responseTimeSeconds"]),
            createdAt: timestampValue(from: data["createdAt"])
        )
    }

    private func decodeMember(from snapshot: DocumentSnapshot) -> Member? {
        let data = snapshot.data() ?? [:]
        let uid = (data["uid"] as? String) ?? snapshot.documentID
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return Member(
            documentId: snapshot.documentID,
            uid: uid,
            pseudo: (data["pseudo"] as? String) ?? "",
            photoUrl: stringValue(from: data["photoUrl"]),
            profileIcon: stringValue(from: data["profileIcon"]),
            xpInCommunity: int64Value(from: data["xpInCommunity"]),
            pendingTorpilleId: stringValue(from: data["pendingTorpilleId"]),
            pendingDeadlineAt: timestampValue(from: data["pendingDeadlineAt"]),
            pendingFromPseudo: stringValue(from: data["pendingFromPseudo"]),
            lastTorpilledAt: timestampValue(from: data["lastTorpilledAt"]),
            lastTorpilleSentAt: timestampValue(from: data["lastTorpilleSentAt"]),
            lastRespondedAt: timestampValue(from: data["lastRespondedAt"]),
            overdueCount: int64Value(from: data["overdueCount"]),
            lastLatitude: doubleValue(from: data["lastLatitude"]),
            lastLongitude: doubleValue(from: data["lastLongitude"]),
            lastLocationUpdatedAt: timestampValue(from: data["lastLocationUpdatedAt"]),
            lastSeenTorpilleAt: timestampValue(from: data["lastSeenTorpilleAt"]),
            lastSeenMessageAt: timestampValue(from: data["lastSeenMessageAt"]),
            lastOpenedAt: timestampValue(from: data["lastOpenedAt"]),
            lastActiveAt: timestampValue(from: data["lastActiveAt"])
        )
    }

    private func decodeMessage(from snapshot: QueryDocumentSnapshot) -> Message? {
        let data = snapshot.data()
        guard let type = data["type"] as? String,
              let senderUid = data["senderUid"] as? String else {
            return nil
        }

        return Message(
            documentId: snapshot.documentID,
            id: (data["id"] as? String) ?? snapshot.documentID,
            type: type,
            senderUid: senderUid,
            senderPseudo: (data["senderPseudo"] as? String) ?? "",
            text: stringValue(from: data["text"]),
            videoUrl: stringValue(from: data["videoUrl"]),
            videoBucket: stringValue(from: data["videoBucket"]),
            videoPath: stringValue(from: data["videoPath"]),
            audioUrl: stringValue(from: data["audioUrl"]),
            audioBucket: stringValue(from: data["audioBucket"]),
            audioPath: stringValue(from: data["audioPath"]),
            audioDurationSeconds: doubleValue(from: data["audioDurationSeconds"]),
            imageUrl: stringValue(from: data["imageUrl"]),
            imageBucket: stringValue(from: data["imageBucket"]),
            imagePath: stringValue(from: data["imagePath"]),
            taggedUid: stringValue(from: data["taggedUid"]),
            taggedPseudo: stringValue(from: data["taggedPseudo"]),
            tagX: doubleValue(from: data["tagX"]),
            tagY: doubleValue(from: data["tagY"]),
            torpilleId: stringValue(from: data["torpilleId"]),
            createdAt: timestampValue(from: data["createdAt"]),
            savedAt: timestampValue(from: data["savedAt"]),
            savedByUid: stringValue(from: data["savedByUid"]),
            savedByPseudo: stringValue(from: data["savedByPseudo"]),
            moderationStatus: stringValue(from: data["moderationStatus"]),
            reportCount: int64Value(from: data["reportCount"])
        )
    }

    private func decodeTorpille(from snapshot: DocumentSnapshot) -> Torpille? {
        let data = snapshot.data() ?? [:]
        let fromUid = stringValue(from: data["fromUid"]) ?? ""
        let communityId = stringValue(from: data["communityId"]) ?? ""
        guard !fromUid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !communityId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return Torpille(
            documentId: snapshot.documentID,
            id: stringValue(from: data["id"]) ?? snapshot.documentID,
            fromUid: fromUid,
            fromPseudo: stringValue(from: data["fromPseudo"]),
            toUid: stringValue(from: data["toUid"]) ?? "",
            communityId: communityId,
            videoUrl: stringValue(from: data["videoUrl"]),
            videoBucket: stringValue(from: data["videoBucket"]),
            videoPath: stringValue(from: data["videoPath"]),
            taggedPseudo: stringValue(from: data["taggedPseudo"]),
            tagX: doubleValue(from: data["tagX"]),
            tagY: doubleValue(from: data["tagY"]),
            createdAt: timestampValue(from: data["createdAt"]),
            deadlineAt: timestampValue(from: data["deadlineAt"]),
            responded: boolValue(from: data["responded"]),
            respondedAt: timestampValue(from: data["respondedAt"]),
            nextToUid: stringValue(from: data["nextToUid"]),
            penaltyApplied: boolValue(from: data["penaltyApplied"]),
            isPublished: boolValue(from: data["isPublished"]),
            publishedAt: timestampValue(from: data["publishedAt"]),
            publishedByUid: stringValue(from: data["publishedByUid"]),
            publishedByPseudo: stringValue(from: data["publishedByPseudo"]),
            communityName: stringValue(from: data["communityName"]),
            moderationStatus: stringValue(from: data["moderationStatus"]),
            reportCount: int64Value(from: data["reportCount"])
        )
    }


    private func memberPayload(uid: String, pseudo: String, photoUrl: String?, profileIcon: String?, xpInCommunity: Int64) -> [String: Any] {
        var payload: [String: Any] = [
            "uid": uid,
            "pseudo": pseudo,
            "xpInCommunity": xpInCommunity
        ]

        if let photoUrl, !photoUrl.isEmpty {
            payload["photoUrl"] = photoUrl
        }

        if let profileIcon, !profileIcon.isEmpty {
            payload["profileIcon"] = profileIcon
        }

        return payload
    }

    private func asInt64(_ rawValue: Any?) -> Int64 {
        if let value = rawValue as? Int64 { return value }
        if let value = rawValue as? Int { return Int64(value) }
        if let value = rawValue as? Double { return Int64(value) }
        return 0
    }

    private func recalculateXP(for uid: String) async throws {
        let communityIds = try await loadCanonicalCommunityIds(for: uid)
        var communityXP: [String: Int64] = [:]
        var validCommunityIds: [String] = []

        for communityId in communityIds {
            let memberSnapshot = try await communities
                .document(communityId)
                .collection("members")
                .document(uid)
                .getDocument()

            guard memberSnapshot.exists else { continue }
            validCommunityIds.append(communityId)
            communityXP[communityId] = asInt64(memberSnapshot.data()?["xpInCommunity"])
        }

        let totalXP = communityXP.values.reduce(Int64(0), +)
        try await users.document(uid).setData([
            "uid": uid,
            "communityIds": validCommunityIds,
            "communityXP": communityXP,
            "xptotal": totalXP,
            "xpTotal": totalXP,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    private func recalculateXPForCurrentUser() async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        try await recalculateXP(for: uid)
    }

    private func refreshCurrentAuthToken() async throws {
        guard let user = auth.currentUser else {
            throw TorpilleError.notAuthenticated
        }
        _ = try await user.getIDTokenResult(forcingRefresh: true)
    }

    @discardableResult
    func syncXPState(communityId: String) async throws -> Bool {
        let penaltyApplied = try await applyExpiredPenaltyIfNeeded(communityId: communityId)
        try await recalculateXPForCurrentUser()
        return penaltyApplied
    }

    @discardableResult
    func syncCommunityXPState(communityId: String) async throws -> Int {
        let penaltyApplied = try await applyExpiredPenaltyIfNeeded(communityId: communityId)
        try await recalculateXPForCurrentUser()
        return penaltyApplied ? 1 : 0
    }

    func syncMyTotalXP() async throws {
        try await recalculateXPForCurrentUser()
    }

    @discardableResult
    func applyExpiredPenaltyIfNeeded(communityId: String) async throws -> Bool {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        let penaltyApplied = try await applyExpiredPenaltyIfNeeded(communityId: communityId, memberUid: uid)
        if penaltyApplied {
            try await recalculateXPForCurrentUser()
        }
        return penaltyApplied
    }

    @discardableResult
    private func applyExpiredPenaltyIfNeeded(communityId: String, memberUid: String) async throws -> Bool {
        let memberRef = communities.document(communityId).collection("members").document(memberUid)
        let transactionResult = try await db.runTransaction { transaction, errorPointer in
            do {
                let memberSnapshot = try transaction.getDocument(memberRef)
                guard memberSnapshot.exists else { return false }

                let memberData = memberSnapshot.data() ?? [:]
                guard let pendingTorpilleId = memberData["pendingTorpilleId"] as? String,
                      !pendingTorpilleId.isEmpty,
                      let pendingDeadlineAt = memberData["pendingDeadlineAt"] as? Timestamp else {
                    return false
                }

                guard pendingDeadlineAt.dateValue() <= Date() else {
                    return false
                }

                let torpRef = self.communities.document(communityId).collection("torpilles").document(pendingTorpilleId)
                let torpSnapshot = try transaction.getDocument(torpRef)
                guard torpSnapshot.exists else { return false }

                let torpData = torpSnapshot.data() ?? [:]
                if (torpData["responded"] as? Bool) == true { return false }
                if (torpData["penaltyApplied"] as? Bool) == true { return false }

                transaction.updateData([
                    "penaltyApplied": true
                ], forDocument: torpRef)

                transaction.updateData([
                    "xpInCommunity": FieldValue.increment(Int64(-10))
                ], forDocument: memberRef)

                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return false
            }
        }

        return (transactionResult as? Bool) ?? false
    }

    func inviteLink(for communityId: String, languageCode: String = "fr") -> String {
        "https://torpille-38783.web.app/join.html?cid=\(communityId)&lang=\(languageCode)"
    }

    func getCommunityOrThrow(_ communityId: String) async throws -> Community {
        let snapshot = try await communities.document(communityId).getDocument()
        guard snapshot.exists else {
            throw TorpilleError.missingData("Communauté introuvable")
        }
        return try snapshot.data(as: Community.self)
    }


    func createCommunity(name: String, isPublic: Bool, responseTimeSeconds: Int64, me: UserProfile) async throws -> String {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try BasicContentFilter.validate(name)
        guard me.hasRequiredIdentity else {
            throw TorpilleError.missingData("Complète obligatoirement ton prénom, ton nom et ton pseudo, puis accepte les règles EULA et la politique de confidentialité avant de créer une communauté.")
        }
        do {
            try await refreshCurrentAuthToken()
        } catch {
            throw TorpilleError.missingData(OperationDiagnostics.message(for: .refreshToken, error: error))
        }
        let doc = communities.document()
        let community = Community(
            id: doc.documentID,
            name: name,
            isPublic: isPublic,
            adminUid: uid,
            responseTimeSeconds: responseTimeSeconds,
            createdAt: Timestamp(date: Date())
        )
        do {
            try doc.setData(from: community)
        } catch {
            throw TorpilleError.missingData(OperationDiagnostics.message(for: .createCommunityDocument, error: error))
        }

        let memberPayload = memberPayload(
            uid: uid,
            pseudo: me.pseudo,
            photoUrl: me.photoUrl,
            profileIcon: me.profileIcon,
            xpInCommunity: 0
        )
        do {
            try await doc.collection("members").document(uid).setData(memberPayload)
        } catch {
            throw TorpilleError.missingData(OperationDiagnostics.message(for: .createAdminMembership, error: error))
        }
        do {
            try await appendCommunityIdToProfile(doc.documentID, for: uid)
        } catch {
            print("⚠️ CommunityRepository.createCommunity appendCommunityIdToProfile failure:", debugDescribe(error))
        }
        do {
            try await markCommunityOpened(doc.documentID)
        } catch {
            print("⚠️ CommunityRepository.createCommunity markCommunityOpened failure:", debugDescribe(error))
        }
        do {
            try await recalculateXPForCurrentUser()
        } catch {
            print(
                "⚠️ CommunityRepository.createCommunity non-blocking XP recalculation failure:",
                OperationDiagnostics.message(for: .recalculateTotalXP, error: error)
            )
        }
        return doc.documentID
    }

    enum JoinCommunityOutcome {
        case joined
        case requestPending
    }

    func joinCommunity(communityId: String, me: UserProfile) async throws -> JoinCommunityOutcome {
        guard auth.currentUser?.uid != nil else { throw TorpilleError.notAuthenticated }
        guard me.hasRequiredIdentity else {
            throw TorpilleError.missingData("Complète ton profil avant de rejoindre une communauté.")
        }
        try await refreshCurrentAuthToken()
        let result = try await functions.httpsCallable("requestCommunityMembership").call([
            "communityId": communityId
        ])
        guard let data = result.data as? [String: Any], let status = data["status"] as? String else {
            throw TorpilleError.missingData("Réponse invalide du serveur.")
        }
        if status == "pending" || status == "already-pending" {
            return .requestPending
        }
        guard status == "joined" || status == "already-member" else {
            throw TorpilleError.missingData("La demande n'a pas pu être traitée.")
        }
        do {
            try await markCommunityOpened(communityId)
        } catch {
            print("⚠️ CommunityRepository.joinCommunity markCommunityOpened failure:", debugDescribe(error))
        }
        do {
            try await recalculateXPForCurrentUser()
        } catch {
            print(
                "⚠️ CommunityRepository.joinCommunity non-blocking XP recalculation failure:",
                OperationDiagnostics.message(for: .recalculateTotalXP, error: error)
            )
        }
        return .joined
    }

    func observePendingJoinRequests(communityId: String, handler: @escaping ([CommunityJoinRequest]) -> Void) -> ListenerRegistration {
        db.collection("communityJoinRequests")
            .whereField("communityId", isEqualTo: communityId)
            .whereField("status", isEqualTo: CommunityJoinRequestStatus.pending.rawValue)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: CommunityJoinRequest.self) } ?? []
                handler(values.sorted { ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast) })
            }
    }

    func resolveJoinRequest(_ request: CommunityJoinRequest, accept: Bool) async throws {
        _ = try await functions.httpsCallable("resolveCommunityJoinRequest").call([
            "requestId": request.id,
            "decision": accept ? "accepted" : "rejected"
        ])
    }

    func updateCommunitySettings(communityId: String, isPublic: Bool, responseTimeSeconds: Int64) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let community = try await getCommunityOrThrow(communityId)
        guard community.adminUid == uid else {
            throw TorpilleError.missingData("Seul l'administrateur peut modifier la communauté.")
        }
        try await communities.document(communityId).updateData([
            "isPublic": isPublic,
            "responseTimeSeconds": responseTimeSeconds
        ])
    }

    func deleteCommunityPermanently(communityId: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let community = try await getCommunityOrThrow(communityId)
        guard community.adminUid == uid else {
            throw TorpilleError.missingData("Seul l'administrateur peut supprimer la communauté.")
        }
        _ = try await functions.httpsCallable("deleteCommunity").call([
            "communityId": communityId
        ])
    }

    func removeMember(communityId: String, memberUid: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let community = try await getCommunityOrThrow(communityId)
        guard community.adminUid == uid else {
            throw TorpilleError.missingData("Seul l'administrateur peut retirer un membre.")
        }
        guard community.isPublic == false else {
            throw TorpilleError.missingData("Cette action est reservee aux communautes privees.")
        }
        guard memberUid != uid else {
            throw TorpilleError.missingData("L'administrateur ne peut pas se retirer lui-meme.")
        }

        try await communities.document(communityId)
            .collection("members")
            .document(memberUid)
            .delete()
    }

    func banMember(communityId: String, member: Member) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let community = try await getCommunityOrThrow(communityId)
        guard community.adminUid == uid else {
            throw TorpilleError.missingData("Seul l'administrateur peut bannir un membre.")
        }
        guard community.isPublic == false else {
            throw TorpilleError.missingData("Cette action est reservee aux communautes privees.")
        }
        guard member.uid != uid else {
            throw TorpilleError.missingData("L'administrateur ne peut pas se bannir lui-meme.")
        }

        let communityRef = communities.document(communityId)
        let batch = db.batch()
        batch.setData([
            "uid": member.uid,
            "pseudo": member.displayName,
            "bannedAt": Timestamp(date: Date()),
            "bannedByUid": uid
        ], forDocument: communityRef.collection("banned").document(member.uid), merge: true)
        batch.deleteDocument(communityRef.collection("members").document(member.uid))
        try await batch.commit()
    }

    func observeCommunity(_ communityId: String, handler: @escaping (Community?) -> Void) -> ListenerRegistration {
        communities.document(communityId).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists else {
                handler(nil)
                return
            }
            handler(try? snapshot.data(as: Community.self))
        }
    }

    func observeCommunitiesForMe(onPartial: (([Community]) -> Void)? = nil, handler: @escaping ([Community]) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler([])
            return nil
        }

        var generation = 0
        return db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
            generation += 1
            let currentGeneration = generation
            guard let self else { return }
            Task {
                let storedIds = (try? await self.loadCanonicalCommunityIds(for: uid)) ?? []
                let membershipIds = self.normalizedCommunityIds(
                    snapshot?.documents.compactMap { $0.reference.parent.parent?.documentID } ?? []
                )
                let mergedIds = CommunityMembershipStore.mergedIDs(
                    primary: storedIds,
                    secondary: membershipIds
                )

                let resolved = await self.resolveCommunities(for: uid, communityIds: mergedIds) { values in
                    guard currentGeneration == generation else { return }
                    onPartial?(values)
                }
                guard currentGeneration == generation else { return }
                handler(resolved.communities)

                if mergedIds != storedIds {
                    do {
                        try await self.setProfileCommunityIds(mergedIds, for: uid)
                    } catch {
                        print("⚠️ CommunityRepository.observeCommunitiesForMe profile merge repair failure:", debugDescribe(error))
                    }
                }

                if resolved.validIds != mergedIds {
                    do {
                        let repairedIds = resolved.validIds.isEmpty ? membershipIds : resolved.validIds
                        try await self.setProfileCommunityIds(repairedIds, for: uid)
                    } catch {
                        print("⚠️ CommunityRepository.observeCommunitiesForMe profile self-heal failure:", debugDescribe(error))
                    }
                }

                if resolved.communities.isEmpty && !mergedIds.isEmpty && !membershipIds.isEmpty {
                    let fallbackResolved = await self.resolveCommunities(for: uid, communityIds: membershipIds)
                    guard currentGeneration == generation else { return }
                    handler(fallbackResolved.communities)
                }
            }
        }
    }

    func markCommunityOpened(_ communityId: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let now = Timestamp(date: Date())
        try await appendCommunityIdToProfile(communityId, for: uid)
        try await communities.document(communityId)
            .collection("members")
            .document(uid)
            .setData([
                "lastOpenedAt": now,
                "lastActiveAt": now
            ], merge: true)
    }

    func markMeActive(in communityIds: [String]) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let now = Timestamp(date: Date())
        for communityId in communityIds where !communityId.isEmpty {
            try await communities.document(communityId)
                .collection("members")
                .document(uid)
                .setData([
                    "lastActiveAt": now
                ], merge: true)
        }
    }

    func myCommunityIds() async throws -> [String] {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let profileIds = try await loadProfileCommunityIds(for: uid)
        let membershipIds = try await loadMembershipCommunityIds(for: uid)
        let merged = CommunityMembershipStore.mergedIDs(primary: profileIds, secondary: membershipIds)
        if merged != profileIds {
            try await setProfileCommunityIds(merged, for: uid)
        }
        return merged
    }

    func observeMembers(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        var currentMembers: [Member] = []
        var currentExcludedUserIds: Set<String> = []
        var hasLoadedPrivacyFilters = false
        var publishGeneration = 0

        func publish(_ members: [Member], excludedUserIds: Set<String>) {
            // Never expose an unfiltered membership snapshot, even briefly,
            // while blocked/blockedBy filters are still loading.
            guard hasLoadedPrivacyFilters else {
                handler([])
                return
            }
            publishGeneration += 1
            let generation = publishGeneration
            Task {
                let enriched = await self.enrichCommunityMembers(members, communityId: communityId)
                guard generation == publishGeneration else { return }
                handler(self.filterMembers(enriched, excluded: excludedUserIds))
            }
        }

        let membersRegistration = communities.document(communityId)
            .collection("members")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else {
                    handler([])
                    return
                }

                let values = snapshot?.documents.compactMap { self.decodeMember(from: $0) } ?? []
                currentMembers = values
                publish(values, excludedUserIds: currentExcludedUserIds)
            }

        // Community-level hiding applies to content only. Keep hidden members
        // in the membership list so the user can find and unhide them later.
        // Account-level blocked/blockedBy relationships remain excluded.
        let excludedRegistration = observeExcludedUserIds(communityId: nil) { excludedUserIds in
            hasLoadedPrivacyFilters = true
            currentExcludedUserIds = excludedUserIds
            publish(currentMembers, excludedUserIds: excludedUserIds)
        }

        return CompositeListenerRegistration([membersRegistration] + [excludedRegistration].compactMap { $0 })
    }

    /// The torpille recipient picker must contain every registered community
    /// member. In particular, it must not inherit the discussion visibility
    /// filters (hidden/blocked members).
    func observeTorpilleTargetMembers(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        var currentMembers: [Member] = []
        var blockedIds: Set<String> = []
        var blockedByIds: Set<String> = []

        func publish() {
            Task {
                let enriched = await self.enrichCommunityMembers(currentMembers, communityId: communityId)
                handler(enriched.filter {
                    blockedIds.contains($0.uid) == false && blockedByIds.contains($0.uid) == false
                })
            }
        }

        let membersRegistration = communities.document(communityId)
            .collection("members")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else {
                    handler([])
                    return
                }

                currentMembers = snapshot?.documents.compactMap { self.decodeMember(from: $0) } ?? []
                publish()
            }

        let blockedRegistration: ListenerRegistration?
        if let uid = auth.currentUser?.uid {
            blockedRegistration = users.document(uid)
                .collection("blockedUsers")
                .addSnapshotListener { snapshot, _ in
                    blockedIds = Set(snapshot?.documents.map(\.documentID) ?? [])
                    publish()
                }
        } else {
            blockedRegistration = nil
        }

        let blockedByRegistration = observeBlockedByUserIds { ids in
            blockedByIds = ids
            publish()
        }

        return CompositeListenerRegistration(
            [membersRegistration] + [blockedRegistration, blockedByRegistration].compactMap { $0 }
        )
    }

    func observeDiscussionParticipants(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        var currentMembers: [Member] = []
        var currentExcludedUserIds: Set<String> = []
        var hasLoadedBlockingFilters = false

        func publish(_ members: [Member], excludedUserIds: Set<String>) {
            guard hasLoadedBlockingFilters else {
                handler([])
                return
            }
            Task {
                let enriched = await self.enrichRegisteredMembersWithUserProfiles(members)
                let filtered = self.filterMembers(self.sortMembersForDisplay(enriched), excluded: excludedUserIds)
                handler(filtered)
            }
        }

        let membersRegistration = communities.document(communityId)
            .collection("members")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else {
                    handler([])
                    return
                }

                let values = snapshot?.documents.compactMap { self.decodeMember(from: $0) } ?? []
                currentMembers = values
                publish(values, excludedUserIds: currentExcludedUserIds)
            }

        // A community-specific mask hides messages and torpilles, not the
        // member entry itself. Only full blocking relationships remove a user
        // from this list; otherwise the "show content again" action would be
        // unreachable.
        let excludedRegistration = observeExcludedUserIds(communityId: nil) { excludedUserIds in
            hasLoadedBlockingFilters = true
            currentExcludedUserIds = excludedUserIds
            publish(currentMembers, excludedUserIds: excludedUserIds)
        }

        return CompositeListenerRegistration([membersRegistration] + [excludedRegistration].compactMap { $0 })
    }

    private func enrichCommunityMembers(_ members: [Member], communityId: String) async -> [Member] {
        let profileBackedMembers = await loadProfileBackedMembers(communityId: communityId)
        var membersByUID = Dictionary(uniqueKeysWithValues: profileBackedMembers.map { ($0.uid, $0) })

        for member in await enrichMembersWithUserProfiles(members) {
            guard !member.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            membersByUID[member.uid] = member
        }

        return sortMembersForDisplay(Array(membersByUID.values))
    }

    private func loadProfileBackedMembers(communityId: String) async -> [Member] {
        let cleanCommunityId = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCommunityId.isEmpty else { return [] }

        do {
            let snapshot = try await users
                .whereField("communityIds", arrayContains: cleanCommunityId)
                .getDocuments()

            return snapshot.documents.compactMap { document in
                let profile = try? document.data(as: UserProfile.self)
                guard let profile else { return nil }
                let uid = profile.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? document.documentID : profile.uid
                let pseudo = profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !pseudo.isEmpty else {
                    return nil
                }

                return Member(
                    documentId: document.documentID,
                    uid: uid,
                    pseudo: pseudo,
                    photoUrl: profile.photoUrl,
                    profileIcon: profile.profileIcon,
                    xpInCommunity: profile.communityXP[cleanCommunityId] ?? 0,
                    lastLatitude: profile.lastLatitude,
                    lastLongitude: profile.lastLongitude,
                    lastLocationUpdatedAt: profile.lastLocationUpdatedAt
                )
            }
        } catch {
            debugLog("CommunityRepository.loadProfileBackedMembers failed", error)
            return []
        }
    }

    private func enrichMembersWithUserProfiles(_ members: [Member]) async -> [Member] {
        guard !members.isEmpty else { return members }

        let profilePairs = await withTaskGroup(of: (String, UserProfile?).self) { group in
            for uid in Set(members.map(\.uid).filter { !$0.isEmpty }) {
                group.addTask { [users = self.users] in
                    let snapshot = try? await users.document(uid).getDocument()
                    let profile = snapshot.flatMap { document -> UserProfile? in
                        guard document.exists else { return nil }
                        return try? document.data(as: UserProfile.self)
                    }
                    return (uid, profile)
                }
            }

            var collected: [(String, UserProfile?)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        let profilesByUID = Dictionary(uniqueKeysWithValues: profilePairs)

        return members.map { member in
            guard let profile = profilesByUID[member.uid] ?? nil else {
                // Keep the membership visible even if its user profile cannot
                // be loaded temporarily. The member document may already hold
                // the pseudo and remains a valid torpille target.
                return member
            }

            var updatedMember = member
            updatedMember.photoUrl = profile.photoUrl
            updatedMember.profileIcon = profile.profileIcon
            if !profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedMember.pseudo = profile.pseudo
            }
            if let profileLatitude = profile.lastLatitude,
               let profileLongitude = profile.lastLongitude {
                let shouldUseProfileLocation: Bool
                if let memberUpdatedAt = member.lastLocationUpdatedAt,
                   let profileUpdatedAt = profile.lastLocationUpdatedAt {
                    shouldUseProfileLocation = profileUpdatedAt.dateValue() >= memberUpdatedAt.dateValue()
                } else {
                    shouldUseProfileLocation = member.lastLatitude == nil || member.lastLongitude == nil
                }

                if shouldUseProfileLocation {
                    updatedMember.lastLatitude = profileLatitude
                    updatedMember.lastLongitude = profileLongitude
                    updatedMember.lastLocationUpdatedAt = profile.lastLocationUpdatedAt ?? member.lastLocationUpdatedAt
                }
            }
            return updatedMember
        }
    }

    private func enrichRegisteredMembersWithUserProfiles(_ members: [Member]) async -> [Member] {
        guard !members.isEmpty else { return members }

        let profilePairs = await withTaskGroup(of: (String, UserProfile?).self) { group in
            for uid in Set(members.map(\.uid).filter { !$0.isEmpty }) {
                group.addTask { [users = self.users] in
                    let snapshot = try? await users.document(uid).getDocument()
                    let profile = snapshot.flatMap { document -> UserProfile? in
                        guard document.exists else { return nil }
                        return try? document.data(as: UserProfile.self)
                    }
                    return (uid, profile)
                }
            }

            var collected: [(String, UserProfile?)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        let profilesByUID = Dictionary(uniqueKeysWithValues: profilePairs)

        return members.map { member in
            guard let profile = profilesByUID[member.uid] ?? nil else {
                return member
            }

            return mergeRegisteredMember(member, with: profile)
        }
    }

    private func mergeRegisteredMember(_ member: Member, with profile: UserProfile) -> Member {
        var updatedMember = member
        updatedMember.photoUrl = profile.photoUrl ?? member.photoUrl
        updatedMember.profileIcon = profile.profileIcon ?? member.profileIcon
        if !profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedMember.pseudo = profile.pseudo
        }
        if let profileLatitude = profile.lastLatitude,
           let profileLongitude = profile.lastLongitude {
            updatedMember.lastLatitude = profileLatitude
            updatedMember.lastLongitude = profileLongitude
            updatedMember.lastLocationUpdatedAt = profile.lastLocationUpdatedAt ?? member.lastLocationUpdatedAt
        }
        return updatedMember
    }

    private func sortMembersForDisplay(_ members: [Member]) -> [Member] {
        members.sorted { lhs, rhs in
            if lhs.xpInCommunity != rhs.xpInCommunity {
                return lhs.xpInCommunity > rhs.xpInCommunity
            }

            let leftName = lhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightName = rhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
    }

    func observeMyMember(_ communityId: String, handler: @escaping (Member?) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler(nil)
            return nil
        }
        return communities.document(communityId)
            .collection("members")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else {
                    handler(nil)
                    return
                }
                guard let snapshot, snapshot.exists,
                      let member = self.decodeMember(from: snapshot) else {
                    handler(nil)
                    return
                }
                Task {
                    let enriched = await self.enrichMembersWithUserProfiles([member]).first
                    handler(enriched)
                }
            }
    }

    func fetchMyMember(communityId: String) async throws -> Member? {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let snapshot = try await communities.document(communityId)
            .collection("members")
            .document(uid)
            .getDocument()
        guard snapshot.exists else { return nil }
        return decodeMember(from: snapshot)
    }

    func observeMessages(_ communityId: String, handler: @escaping ([Message]) -> Void) -> ListenerRegistration {
        var currentMessages: [Message] = []
        var currentExcludedUserIds: Set<String> = []

        func publish(_ messages: [Message], excludedUserIds: Set<String>) {
            let visible = messages.filter { self.isMessageVisibleInDiscussion($0) }
            handler(self.filterMessages(visible, excluded: excludedUserIds))
        }

        let messagesRegistration = communities.document(communityId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { self.decodeMessage(from: $0) } ?? []
                currentMessages = values
                let expired = values.filter { self.isExpiredUnsavedMessage($0) }
                if !expired.isEmpty {
                    Task { try? await self.deleteExpiredMessages(communityId: communityId, messages: expired) }
                }
                publish(values, excludedUserIds: currentExcludedUserIds)
            }

        let excludedRegistration = observeExcludedUserIds(communityId: communityId) { excludedUserIds in
            currentExcludedUserIds = excludedUserIds
            publish(currentMessages, excludedUserIds: excludedUserIds)
        }

        return CompositeListenerRegistration([messagesRegistration] + [excludedRegistration].compactMap { $0 })
    }

    func observeSavedMessages(_ communityId: String, handler: @escaping ([Message]) -> Void) -> ListenerRegistration {
        var currentMessages: [Message] = []
        var currentExcludedUserIds: Set<String> = []

        func publish(_ messages: [Message], excludedUserIds: Set<String>) {
            handler(self.filterMessages(messages, excluded: excludedUserIds))
        }

        let messagesRegistration = communities.document(communityId)
            .collection("savedMessages")
            .order(by: "savedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { self.decodeMessage(from: $0) } ?? []
                currentMessages = values
                publish(values, excludedUserIds: currentExcludedUserIds)
            }

        let excludedRegistration = observeExcludedUserIds(communityId: communityId) { excludedUserIds in
            currentExcludedUserIds = excludedUserIds
            publish(currentMessages, excludedUserIds: excludedUserIds)
        }

        return CompositeListenerRegistration([messagesRegistration] + [excludedRegistration].compactMap { $0 })
    }

    private func isTorpilleMessage(_ message: Message) -> Bool {
        message.torpilleId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func isExpiredMessage(_ message: Message, now: Date = Date()) -> Bool {
        guard let createdAt = message.createdAt?.dateValue() else { return false }
        let retentionInterval = isTorpilleMessage(message) ? torpilleRetentionInterval : messageRetentionInterval
        return now.timeIntervalSince(createdAt) >= retentionInterval
    }

    private func isExpiredUnsavedMessage(_ message: Message, now: Date = Date()) -> Bool {
        !message.isSaved && isExpiredMessage(message, now: now)
    }

    private func isMessageVisibleInDiscussion(_ message: Message, now: Date = Date()) -> Bool {
        if isTorpilleMessage(message), isExpiredMessage(message, now: now) {
            return false
        }
        return message.isSaved || !isExpiredUnsavedMessage(message, now: now)
    }

    private func deleteExpiredMessages(communityId: String, messages: [Message]) async throws {
        let references = messages.compactMap { message -> DocumentReference? in
            guard let messageId = message.id, !messageId.isEmpty else { return nil }
            return communities.document(communityId).collection("messages").document(messageId)
        }
        try await commitDeleteChunks(for: references)
    }

    func saveMessage(communityId: String, messageId: String, savedByPseudo: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let communityRef = communities.document(communityId)
        let messageRef = communityRef.collection("messages").document(messageId)
        let savedMessageRef = communityRef.collection("savedMessages").document(messageId)
        let savedAt = Timestamp(date: Date())

        let snapshot = try await messageRef.getDocument()
        guard snapshot.exists else {
            throw TorpilleError.missingData("Contenu introuvable")
        }

        var message = try snapshot.data(as: Message.self)
        message.id = messageId
        message.savedAt = savedAt
        message.savedByUid = uid
        message.savedByPseudo = savedByPseudo

        let batch = db.batch()
        batch.setData([
            "savedAt": savedAt,
            "savedByUid": uid,
            "savedByPseudo": savedByPseudo
        ], forDocument: messageRef, merge: true)
        try batch.setData(from: message, forDocument: savedMessageRef)
        try await batch.commit()
    }

    func sendText(communityId: String, senderPseudo: String, text: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try BasicContentFilter.validate(text)
        print("📍 CommunityRepository.sendText")
        print("💬 communityId =", communityId)
        print("💬 uid =", uid)
        print("💬 senderPseudo =", senderPseudo)
        print("💬 text =", text)
        let payload: [String: Any] = [
            "type": "text",
            "senderUid": uid,
            "senderPseudo": senderPseudo,
            "text": text,
            "moderationStatus": "pending",
            "reportCount": 0,
            "createdAt": Timestamp(date: Date())
        ]
        do {
            _ = try await communities.document(communityId).collection("messages").addDocument(data: payload)
            print("✅ sendText addDocument ok")
        } catch {
            debugLog("CommunityRepository.sendText addDocument failed", error)
            throw error
        }
    }

    func sendImageMessage(communityId: String, senderPseudo: String, localFileURL: URL) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let fileExtension = localFileURL.pathExtension.isEmpty ? "jpg" : localFileURL.pathExtension.lowercased()
        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))_\(uid).\(fileExtension)"
        let uploaded = try await videoTransfer.uploadCommunityImage(communityId: communityId, localFileURL: localFileURL, filename: filename)

        let payload: [String: Any] = [
            "type": "image",
            "senderUid": uid,
            "senderPseudo": senderPseudo,
            "imageUrl": uploaded.downloadURL,
            "imageBucket": uploaded.bucket,
            "imagePath": uploaded.storagePath,
            "moderationStatus": "pending",
            "reportCount": 0,
            "createdAt": Timestamp(date: Date())
        ]

        _ = try await communities.document(communityId).collection("messages").addDocument(data: payload)
    }

    func sendCapturedVideoMessage(communityId: String, senderPseudo: String, localFileURL: URL) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let fileExtension = localFileURL.pathExtension.isEmpty ? "mov" : localFileURL.pathExtension.lowercased()
        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))_\(uid).\(fileExtension)"
        let uploaded = try await videoTransfer.uploadCommunityVideo(communityId: communityId, localFileURL: localFileURL, filename: filename)

        let payload: [String: Any] = [
            "type": "video",
            "senderUid": uid,
            "senderPseudo": senderPseudo,
            "videoBucket": uploaded.bucket,
            "videoPath": uploaded.storagePath,
            "videoUrl": uploaded.downloadURL,
            "moderationStatus": "pending",
            "reportCount": 0,
            "createdAt": Timestamp(date: Date())
        ]

        _ = try await communities.document(communityId).collection("messages").addDocument(data: payload)
    }

    func observeRecentTorpilles(_ communityId: String, handler: @escaping ([Torpille]) -> Void) -> ListenerRegistration {
        var currentTorpilles: [Torpille] = []
        var currentExcludedUserIds: Set<String> = []

        func publish(_ torpilles: [Torpille], excludedUserIds: Set<String>) {
            handler(self.filterTorpilles(torpilles, excluded: excludedUserIds))
        }

        let torpillesRegistration = communities.document(communityId)
            .collection("torpilles")
            .order(by: "createdAt", descending: true)
            .limit(to: 40)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { self.decodeTorpille(from: $0) } ?? []
                currentTorpilles = values
                publish(values, excludedUserIds: currentExcludedUserIds)
            }

        let excludedRegistration = observeExcludedUserIds(communityId: communityId) { excludedUserIds in
            currentExcludedUserIds = excludedUserIds
            publish(currentTorpilles, excludedUserIds: excludedUserIds)
        }

        return CompositeListenerRegistration([torpillesRegistration] + [excludedRegistration].compactMap { $0 })
    }

    func markTorpillesSeen(communityId: String, upTo timestamp: Timestamp? = nil) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try await communities.document(communityId).collection("members").document(uid).setData([
            "lastSeenTorpilleAt": timestamp ?? Timestamp(date: Date())
        ], merge: true)
    }

    func markMessagesSeen(communityId: String, upTo timestamp: Timestamp) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try await communities.document(communityId).collection("members").document(uid).setData([
            "lastSeenMessageAt": timestamp
        ], merge: true)
    }

    func sendAudioMessage(communityId: String, senderPseudo: String, localFileURL: URL, durationSeconds: Double) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }

        print("📍 CommunityRepository.sendAudioMessage")
        print("🔐 auth.currentUser =", auth.currentUser?.uid ?? "nil")
        print("🔐 auth email =", auth.currentUser?.email ?? "nil")

        do {
            let token = try await auth.currentUser?.getIDTokenResult(forcingRefresh: false)
            print("✅ ID token refresh ok")
            print("🔐 token =", token?.token.prefix(20) ?? "nil")
        } catch {
            debugLog("CommunityRepository.sendAudioMessage getIDTokenResult failed", error)
            throw error
        }

        print("🎤 communityId =", communityId)
        print("🎤 senderPseudo =", senderPseudo)
        print("🎤 localFileURL =", localFileURL.path)
        print("🎤 file exists =", FileManager.default.fileExists(atPath: localFileURL.path))
        do {
            let values = try localFileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            print("🎤 file size =", values.fileSize ?? -1)
            print("🎤 content type =", values.contentType?.preferredMIMEType ?? "nil")
        } catch {
            print("🔥 Unable to inspect local audio file:", error)
        }

        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))_\(uid).m4a"
        let uploaded: UploadedAudio
        do {
            uploaded = try await videoTransfer.uploadCommunityAudio(
                communityId: communityId,
                localFileURL: localFileURL,
                filename: filename,
                durationSeconds: durationSeconds
            )
            print("✅ audio upload ok")
            print("bucket =", uploaded.bucket)
            print("path =", uploaded.storagePath)
        } catch {
            debugLog("CommunityRepository.sendAudioMessage uploadCommunityAudio failed", error)
            throw error
        }

        let payload: [String: Any] = [
            "type": "audio",
            "senderUid": uid,
            "senderPseudo": senderPseudo,
            "audioBucket": uploaded.bucket,
            "audioPath": uploaded.storagePath,
            "audioUrl": uploaded.downloadURL,
            "audioDurationSeconds": uploaded.durationSeconds,
            "moderationStatus": "pending",
            "reportCount": 0,
            "createdAt": Timestamp(date: Date())
        ]
        do {
            _ = try await communities.document(communityId).collection("messages").addDocument(data: payload)
            print("✅ sendText addDocument ok")
        } catch {
            debugLog("CommunityRepository.sendText addDocument failed", error)
            throw error
        }
    }

    func getSignedPlaybackURL(videoPath: String, videoBucket: String?) async throws -> URL {
        try await videoTransfer.resolvePlaybackURL(videoPath: videoPath, videoBucket: videoBucket)
    }

    func getStoragePlaybackURL(path: String, bucket: String?) async throws -> URL {
        try await videoTransfer.resolveStoragePlaybackURL(path: path, bucket: bucket)
    }

    func observePublishedReels(limit: Int = 40, handler: @escaping ([PublishedReel]) -> Void) -> ListenerRegistration {
        var currentReels: [PublishedReel] = []
        var currentBlockedUserIds: Set<String> = []

        func publish(_ reels: [PublishedReel], blockedUserIds: Set<String>) {
            Task {
                let filtered = self.filterReels(reels, blockedUserIds: blockedUserIds)
                handler(await self.enrichReelsWithAuthorProfiles(filtered))
            }
        }

        let reelsRegistration = reels
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { doc -> PublishedReel? in
                    var value = try? doc.data(as: PublishedReel.self)
                    value?.id = doc.documentID
                    return value
                } ?? []
                currentReels = values
                publish(values, blockedUserIds: currentBlockedUserIds)
            }

        let blockedRegistration = observeExcludedUserIds(communityId: nil) { blockedUserIds in
            currentBlockedUserIds = blockedUserIds
            publish(currentReels, blockedUserIds: blockedUserIds)
        }

        return CompositeListenerRegistration([reelsRegistration] + [blockedRegistration].compactMap { $0 })
    }

    func observePublishedReelsForCommunity(_ communityId: String, handler: @escaping ([PublishedReel]) -> Void) -> ListenerRegistration {
        var currentReels: [PublishedReel] = []
        var currentBlockedUserIds: Set<String> = []

        func publish(_ reels: [PublishedReel], blockedUserIds: Set<String>) {
            Task {
                let filtered = self.filterReels(reels, blockedUserIds: blockedUserIds)
                let enriched = await self.enrichReelsWithAuthorProfiles(filtered)
                handler(enriched.sorted { ($0.publishedAt?.dateValue() ?? .distantPast) > ($1.publishedAt?.dateValue() ?? .distantPast) })
            }
        }

        let reelsRegistration = reels
            .whereField("communityId", isEqualTo: communityId)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { doc -> PublishedReel? in
                    var value = try? doc.data(as: PublishedReel.self)
                    value?.id = doc.documentID
                    return value
                } ?? []
                currentReels = values
                publish(values, blockedUserIds: currentBlockedUserIds)
            }

        let blockedRegistration = observeExcludedUserIds(communityId: nil) { blockedUserIds in
            currentBlockedUserIds = blockedUserIds
            publish(currentReels, blockedUserIds: blockedUserIds)
        }

        return CompositeListenerRegistration([reelsRegistration] + [blockedRegistration].compactMap { $0 })
    }

    func publicUserProfile(uid: String) async throws -> UserProfile {
        let cleanUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUID.isEmpty else {
            throw TorpilleError.missingData("Profil introuvable.")
        }

        let snapshot = try await users.document(cleanUID).getDocument()
        guard snapshot.exists else {
            throw TorpilleError.missingData("Profil introuvable.")
        }

        var profile = try snapshot.data(as: UserProfile.self)
        if profile.uid.isEmpty {
            profile.uid = cleanUID
        }
        return profile
    }

    func publishSavedTorpilleToReels(communityId: String, message: Message) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard let torpilleId = message.torpilleId?.trimmingCharacters(in: .whitespacesAndNewlines), !torpilleId.isEmpty else {
            throw TorpilleError.missingData("Seules les torpilles enregistrées peuvent être publiées en Memories.")
        }

        let community = try await getCommunityOrThrow(communityId)
        let torpilleRef = communities.document(communityId).collection("torpilles").document(torpilleId)
        let savedMessageRef = communities.document(communityId).collection("savedMessages").document(message.stableId)
        let reelRef = reels.document(torpilleId)

        let torpilleSnapshot = try await torpilleRef.getDocument()
        guard torpilleSnapshot.exists else {
            throw TorpilleError.missingData("Torpille introuvable.")
        }

        let savedMessageSnapshot = try await savedMessageRef.getDocument()
        guard savedMessageSnapshot.exists else {
            throw TorpilleError.missingData("Cette torpille doit d'abord être enregistrée dans la conversation.")
        }

        guard let torpille = decodeTorpille(from: torpilleSnapshot) else {
            throw TorpilleError.missingData("Impossible de lire cette torpille.")
        }
        guard torpille.fromUid == uid else {
            throw TorpilleError.missingData("Tu peux publier uniquement tes propres torpilles.")
        }

        if torpille.isPublished {
            throw TorpilleError.missingData("Cette torpille est déjà publiée dans Memories.")
        }

        let publishedAt = Timestamp(date: Date())
        let batch = db.batch()
        batch.setData([
            "isPublished": true,
            "publishedAt": publishedAt,
            "publishedByUid": uid,
            "publishedByPseudo": message.senderPseudo,
            "communityName": community.name
        ], forDocument: torpilleRef, merge: true)

        try batch.setData(from: PublishedReel(
            id: torpilleId,
            torpilleId: torpilleId,
            sourceMessageId: message.stableId,
            communityId: communityId,
            communityName: community.name,
            authorUid: uid,
            authorPseudo: message.senderPseudo,
            videoUrl: message.videoUrl,
            videoBucket: message.videoBucket,
            videoPath: message.videoPath,
            taggedPseudo: message.taggedPseudo,
            createdAt: message.createdAt,
            publishedAt: publishedAt,
            moderationStatus: "pending",
            reportCount: 0
        ), forDocument: reelRef)
        try await batch.commit()
    }

    func unpublishSavedTorpilleFromReels(communityId: String, message: Message) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard let torpilleId = message.torpilleId?.trimmingCharacters(in: .whitespacesAndNewlines), !torpilleId.isEmpty else {
            throw TorpilleError.missingData("Ce contenu n'est pas une torpille publiée.")
        }

        let torpilleRef = communities.document(communityId).collection("torpilles").document(torpilleId)
        let reelRef = reels.document(torpilleId)
        let torpilleSnapshot = try await torpilleRef.getDocument()
        guard torpilleSnapshot.exists, let torpille = decodeTorpille(from: torpilleSnapshot) else {
            throw TorpilleError.missingData("Torpille introuvable.")
        }
        guard torpille.fromUid == uid else {
            throw TorpilleError.missingData("Seul l'auteur peut retirer cette torpille des Memories.")
        }

        let batch = db.batch()
        batch.setData([
            "isPublished": false,
            "publishedAt": FieldValue.delete(),
            "publishedByUid": FieldValue.delete(),
            "publishedByPseudo": FieldValue.delete(),
            "communityName": FieldValue.delete()
        ], forDocument: torpilleRef, merge: true)
        batch.deleteDocument(reelRef)
        try await batch.commit()
    }

    func unpublishReel(_ reel: PublishedReel) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard reel.authorUid == uid else {
            throw TorpilleError.missingData("Seul l'auteur peut retirer cette torpille des Memories.")
        }

        let torpilleRef = communities.document(reel.communityId).collection("torpilles").document(reel.torpilleId)
        let batch = db.batch()
        batch.setData([
            "isPublished": false,
            "publishedAt": FieldValue.delete(),
            "publishedByUid": FieldValue.delete(),
            "publishedByPseudo": FieldValue.delete(),
            "communityName": FieldValue.delete()
        ], forDocument: torpilleRef, merge: true)
        batch.deleteDocument(reels.document(reel.torpilleId))
        try await batch.commit()
    }

    func sendVideoTorpille(
        communityId: String,
        senderPseudo: String,
        localFileURL: URL,
        taggedUid: String?,
        taggedPseudo: String,
        publishToReels: Bool,
        tagX: Double,
        tagY: Double
    ) async throws {
        try await sendVideoTorpilleRaw(
            communityId: communityId,
            senderPseudo: senderPseudo,
            localFileURL: localFileURL,
            taggedUid: taggedUid,
            taggedPseudo: taggedPseudo,
            publishToReels: publishToReels,
            tagX: tagX,
            tagY: tagY
        )
    }

    private func sendVideoTorpilleRaw(
        communityId: String,
        senderPseudo: String,
        localFileURL: URL,
        taggedUid: String?,
        taggedPseudo: String,
        publishToReels: Bool,
        tagX: Double,
        tagY: Double
    ) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }

        print("🔐 currentUser.uid =", uid)
        print("🔐 currentUser.email =", auth.currentUser?.email ?? "nil")

        do {
            if let token = try await auth.currentUser?.getIDTokenResult(forcingRefresh: false) {
                print("✅ ID token refresh ok")
                print("🔐 token authTime =", token.authDate)
                print("🔐 token expiration =", token.expirationDate)
                print("🔐 token claims =", token.claims)
            } else {
                print("🔥 getIDTokenResult returned nil")
            }
        } catch {
            let nsError = error as NSError
            print("🔥 getIDTokenResult failed")
            print("domain =", nsError.domain)
            print("code =", nsError.code)
            print("userInfo =", nsError.userInfo)
            throw error
        }

        print("📍 1. getCommunityOrThrow")
        _ = try await getCommunityOrThrow(communityId)

        let fileExtension = localFileURL.pathExtension.isEmpty ? "mov" : localFileURL.pathExtension.lowercased()
        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))_\(uid).\(fileExtension)"

        print("🎥 localFileURL =", localFileURL.path)
        print("🎥 file exists =", FileManager.default.fileExists(atPath: localFileURL.path))
        do {
            let values = try localFileURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            print("🎥 file size =", values.fileSize ?? -1)
            print("🎥 content type =", values.contentType?.preferredMIMEType ?? "nil")
        } catch {
            print("🔥 Unable to inspect local video file:", error)
        }

        print("📍 2. uploadCommunityVideo")
        let uploaded: UploadedVideo
        do {
            uploaded = try await videoTransfer.uploadCommunityVideo(
                communityId: communityId,
                localFileURL: localFileURL,
                filename: filename
            )
            print("✅ upload ok bucket=\(uploaded.bucket) path=\(uploaded.storagePath)")
        } catch {
            debugLog("CommunityRepository.sendVideoTorpille uploadCommunityVideo failed", error)
            throw error
        }

        // Metadata creation is server-side and atomic: the torpille cannot be
        // created without its corresponding discussion message.
        _ = try await functions.httpsCallable("createVideoTorpille").call([
            "communityId": communityId,
            "senderPseudo": senderPseudo,
            "taggedUid": taggedUid ?? "",
            "taggedPseudo": taggedPseudo,
            "videoBucket": uploaded.bucket,
            "videoPath": uploaded.storagePath,
            "videoUrl": uploaded.downloadURL,
            "tagX": tagX,
            "tagY": tagY
        ])
        try? await recalculateXPForCurrentUser()

    }


    func respondWithVideo(
        communityId: String,
        senderPseudo: String,
        localFileURL: URL,
        pendingTorpilleId: String,
        nextTaggedUid: String,
        nextTaggedPseudo: String,
        publishToReels: Bool,
        tagX: Double,
        tagY: Double
    ) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        _ = try await applyExpiredPenaltyIfNeeded(communityId: communityId)

        let torpRef = communities.document(communityId).collection("torpilles").document(pendingTorpilleId)
        let torpSnapshot = try await torpRef.getDocument()
        guard torpSnapshot.exists else {
            throw TorpilleError.missingData("Torpille introuvable")
        }
        guard let torp = decodeTorpille(from: torpSnapshot) else {
            throw TorpilleError.missingData("Impossible de lire cette torpille.")
        }
        guard torp.toUid == uid else {
            throw TorpilleError.missingData("Cette torpille ne t'est pas destinée")
        }

        print("📍 CommunityRepository.respondWithVideo")
        print("🎥 response localFileURL =", localFileURL.path)
        print("🎥 response file exists =", FileManager.default.fileExists(atPath: localFileURL.path))
        let now = Timestamp(date: Date())
        let isLateResponse = (torp.deadlineAt?.dateValue() ?? .distantFuture) < now.dateValue()
        let recoveryXP: Int64 = isLateResponse ? 5 : 0

        let batch = db.batch()
        batch.updateData([
            "responded": true,
            "respondedAt": now,
            "nextToUid": nextTaggedUid
        ], forDocument: torpRef)
        batch.updateData([
            "pendingTorpilleId": FieldValue.delete(),
            "pendingDeadlineAt": FieldValue.delete(),
            "pendingFromPseudo": FieldValue.delete(),
            "lastRespondedAt": now,
            "xpInCommunity": FieldValue.increment(recoveryXP)
        ], forDocument: communities.document(communityId).collection("members").document(uid))
        do {
            try await batch.commit()
            print("✅ respondWithVideo pre-batch commit ok")
            do {
                try await recalculateXPForCurrentUser()
            } catch {
                print("⚠️ CommunityRepository.respondWithVideo recalculateXPForCurrentUser failure:", debugDescribe(error))
            }
        } catch {
            debugLog("CommunityRepository.respondWithVideo pre-batch commit failed", error)
            throw error
        }

        try await sendVideoTorpilleRaw(
            communityId: communityId,
            senderPseudo: senderPseudo,
            localFileURL: localFileURL,
            taggedUid: nextTaggedUid,
            taggedPseudo: nextTaggedPseudo,
            publishToReels: publishToReels,
            tagX: tagX,
            tagY: tagY
        )

    }

    func updateMyLocation(in communityIds: [String], latitude: Double, longitude: Double) async throws -> Bool {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let now = Timestamp(date: Date())
        let userReference = users.document(uid)
        let didPublish = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(userReference)
                if snapshot.data()?["isGhostMode"] as? Bool == true {
                    return false
                }
                transaction.setData([
                    "uid": uid,
                    "lastLatitude": latitude,
                    "lastLongitude": longitude,
                    "lastLocationUpdatedAt": now,
                    "updatedAt": now
                ], forDocument: userReference, merge: true)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return false
            }
        } as? Bool ?? false

        guard didPublish else { return false }

        for communityId in communityIds where !communityId.isEmpty {
            let memberReference = communities.document(communityId)
                .collection("members")
                .document(uid)
            do {
                try await memberReference.updateData([
                    "lastLatitude": latitude,
                    "lastLongitude": longitude,
                    "lastLocationUpdatedAt": now
                ])
            } catch {
                // The profile remains the source of truth. Map reads enrich member
                // documents from /users/{uid}, so one stale membership must not
                // prevent location from working everywhere else.
                debugLog("CommunityRepository.updateMyLocation member sync failed for \(communityId)", error)
            }
        }
        return true
    }

    func isGhostModeEnabled() async throws -> Bool {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        return try await users.document(uid).getDocument().data()?["isGhostMode"] as? Bool ?? false
    }

    func setGhostMode(_ enabled: Bool, in communityIds: [String]) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        var profileUpdate: [String: Any] = [
            "isGhostMode": enabled,
            "updatedAt": Timestamp(date: Date())
        ]
        if enabled {
            profileUpdate["lastLatitude"] = FieldValue.delete()
            profileUpdate["lastLongitude"] = FieldValue.delete()
            profileUpdate["lastLocationUpdatedAt"] = FieldValue.delete()
        }
        try await users.document(uid).setData(profileUpdate, merge: true)

        guard enabled else { return }
        for communityId in communityIds where !communityId.isEmpty {
            do {
                try await communities.document(communityId).collection("members").document(uid).updateData([
                    "lastLatitude": FieldValue.delete(),
                    "lastLongitude": FieldValue.delete(),
                    "lastLocationUpdatedAt": FieldValue.delete()
                ])
            } catch {
                debugLog("CommunityRepository.setGhostMode member sync failed for \(communityId)", error)
            }
        }
    }

    func observeMembersForMap(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        var publishGeneration = 0
        return observeMembers(communityId) { [weak self] members in
            guard let self else {
                handler(members)
                return
            }
            publishGeneration += 1
            let generation = publishGeneration
            Task {
                let enriched = await self.enrichMembersWithUserLocations(members)
                guard generation == publishGeneration else { return }
                handler(enriched)
            }
        }
    }

    private func enrichMembersWithUserLocations(_ members: [Member]) async -> [Member] {
        await withTaskGroup(of: Member.self, returning: [Member].self) { group in
            for member in members {
                group.addTask {
                    await self.enrichMemberWithUserLocation(member)
                }
            }

            var enriched: [Member] = []
            for await member in group {
                enriched.append(member)
            }
            return enriched.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private func enrichMemberWithUserLocation(_ member: Member) async -> Member {
        guard !member.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return member
        }

        do {
            let snapshot = try await users.document(member.uid).getDocument()
            let data = snapshot.data() ?? [:]
            if data["isGhostMode"] as? Bool == true {
                var hiddenMember = member
                hiddenMember.lastLatitude = nil
                hiddenMember.lastLongitude = nil
                hiddenMember.lastLocationUpdatedAt = nil
                return hiddenMember
            }
            guard let profileLatitude = doubleValue(from: data["lastLatitude"]),
                  let profileLongitude = doubleValue(from: data["lastLongitude"]) else {
                return member
            }

            let profileUpdatedAt = timestampValue(from: data["lastLocationUpdatedAt"])
            if member.lastLatitude != nil,
               member.lastLongitude != nil,
               let memberUpdatedAt = member.lastLocationUpdatedAt,
               let profileUpdatedAt,
               memberUpdatedAt.dateValue() >= profileUpdatedAt.dateValue() {
                return member
            }

            var enriched = member
            enriched.lastLatitude = profileLatitude
            enriched.lastLongitude = profileLongitude
            enriched.lastLocationUpdatedAt = profileUpdatedAt ?? member.lastLocationUpdatedAt
            return enriched
        } catch {
            return member
        }
    }

    func hideMemberContent(communityId: String, member: Member) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard member.uid != uid else {
            throw TorpilleError.missingData("Tu ne peux pas masquer ton propre contenu.")
        }

        var payload: [String: Any] = [
            "uid": member.uid,
            "pseudo": member.displayName,
            "createdAt": Timestamp(date: Date())
        ]
        if let photoUrl = member.photoUrl, !photoUrl.isEmpty {
            payload["photoUrl"] = photoUrl
        }
        if let profileIcon = member.profileIcon, !profileIcon.isEmpty {
            payload["profileIcon"] = profileIcon
        }

        try await users.document(uid)
            .collection("contentFilters")
            .document(communityId)
            .collection("hiddenMembers")
            .document(member.uid)
            .setData(payload, merge: true)
    }

    func showMemberContent(communityId: String, memberUid: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try await users.document(uid)
            .collection("contentFilters")
            .document(communityId)
            .collection("hiddenMembers")
            .document(memberUid)
            .delete()
    }

    func blockUser(_ member: Member) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        guard member.uid != uid else {
            throw TorpilleError.missingData("Tu ne peux pas te bloquer toi-même.")
        }

        var payload: [String: Any] = [
            "blockedUid": member.uid,
            "pseudo": member.displayName,
            "createdAt": Timestamp(date: Date())
        ]
        if let photoUrl = member.photoUrl, !photoUrl.isEmpty {
            payload["photoUrl"] = photoUrl
        }
        if let profileIcon = member.profileIcon, !profileIcon.isEmpty {
            payload["profileIcon"] = profileIcon
        }

        let batch = db.batch()
        batch.setData(payload, forDocument: users.document(uid)
            .collection("blockedUsers")
            .document(member.uid), merge: true)
        batch.deleteDocument(users.document(uid).collection("friends").document(member.uid))
        batch.deleteDocument(users.document(member.uid).collection("friends").document(uid))
        try await batch.commit()
    }

    func unblockUser(_ blockedUid: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try await users.document(uid)
            .collection("blockedUsers")
            .document(blockedUid)
            .delete()
    }

    func observeBlockedUsers(handler: @escaping ([BlockedUser]) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler([])
            return nil
        }

        return users.document(uid)
            .collection("blockedUsers")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { document -> BlockedUser? in
                    guard var blocked = try? document.data(as: BlockedUser.self) else {
                        return nil
                    }
                    if blocked.blockedUid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        blocked.blockedUid = document.documentID
                    }
                    return blocked
                } ?? []
                handler(values)
            }
    }

    func reportContent(
        communityId: String?,
        contentId: String,
        contentType: ReportedContentType,
        authorUid: String?,
        authorPseudo: String?,
        reason: ReportReason,
        details: String
    ) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let cleanContentId = contentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContentId.isEmpty else {
            throw TorpilleError.missingData("Contenu introuvable.")
        }

        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanDetails.count <= 1_000 else {
            throw TorpilleError.missingData("Le contexte du signalement est limité à 1 000 caractères.")
        }
        var payload: [String: Any] = [
            "reporterUid": uid,
            "contentId": cleanContentId,
            "contentType": contentType.rawValue,
            "reason": reason.rawValue,
            "details": cleanDetails,
            "status": "open",
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]
        if let communityId, !communityId.isEmpty {
            payload["communityId"] = communityId
        }
        if let authorUid, !authorUid.isEmpty {
            payload["authorUid"] = authorUid
        }
        if let authorPseudo, !authorPseudo.isEmpty {
            payload["authorPseudo"] = authorPseudo
        }
        try await reports.addDocument(data: payload)
    }
}
    
