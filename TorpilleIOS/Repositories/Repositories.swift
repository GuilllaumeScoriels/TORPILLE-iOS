import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

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

final class AuthRepository {
    private let auth = Auth.auth()

    var currentUID: String { auth.currentUser?.uid ?? "" }
    var currentEmail: String { auth.currentUser?.email ?? "" }

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

    func signOut() throws {
        try auth.signOut()
    }
}

final class UserRepository {
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let transferService = VideoTransferService()

    private var users: CollectionReference { db.collection("users") }
    private var pseudos: CollectionReference { db.collection("pseudos") }

    private func decodeUserProfile(from snapshot: DocumentSnapshot, fallbackUID: String) -> UserProfile {
        let data = snapshot.data() ?? [:]
        return UserProfile(
            documentId: snapshot.documentID,
            uid: (data["uid"] as? String) ?? fallbackUID,
            email: (data["email"] as? String) ?? auth.currentUser?.email,
            pseudo: (data["pseudo"] as? String) ?? "",
            pseudoKey: (data["pseudoKey"] as? String) ?? "",
            photoUrl: data["photoUrl"] as? String,
            profileIcon: data["profileIcon"] as? String,
            xpTotal: (data["xpTotal"] as? Int64) ?? Int64(data["xpTotal"] as? Int ?? 0),
            fcmToken: data["fcmToken"] as? String,
            updatedAt: data["updatedAt"] as? Timestamp
        )
    }

    func getMeOrThrow() async throws -> UserProfile {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        do {
            let snapshot = try await users.document(uid).getDocument()
            guard snapshot.exists else {
                throw TorpilleError.missingData("Profil introuvable")
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

    func observeGlobalLeaderboard(limit: Int = 100, handler: @escaping ([UserProfile]) -> Void) -> ListenerRegistration {
        users
            .order(by: "xpTotal", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else {
                    handler([])
                    return
                }

                let values = snapshot?.documents.map { document in
                    self.decodeUserProfile(from: document, fallbackUID: document.documentID)
                } ?? []

                handler(values)
            }
    }

    func upsertProfile(pseudo: String, photoURL: String?, profileIcon: String?) async throws {
        guard let uid = auth.currentUser?.uid else {
            throw TorpilleError.notAuthenticated
        }

        print("📍 UserRepository.upsertProfile")
        print("👤 uid =", uid)
        print("👤 pseudo =", pseudo)
        print("👤 photoURL =", photoURL ?? "nil")
        print("👤 profileIcon =", profileIcon ?? "nil")

        let clean = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
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

        var payload: [String: Any] = [
            "uid": uid,
            "pseudo": clean,
            "pseudoKey": pseudoKey,
            "updatedAt": now
        ]

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

        if !userSnapshot.exists || currentKey.isEmpty || currentKey == pseudoKey {
            do {
                try await userRef.setData(payload, merge: true)
                return
            } catch {
                debugLog("UserRepository.upsertProfile direct setData failed", error)
                throw error
            }
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
                            userInfo: [NSLocalizedDescriptionKey: "Ce pseudo est déjà utilisé."]
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
                    transaction.deleteDocument(self.pseudos.document(currentKey))
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            debugLog("UserRepository.upsertProfile transaction failed", error)
            throw error
        }
    }

    func updateProfile(pseudo: String, imageData: Data?, profileIcon: String?) async throws {
        print("📍 UserRepository.updateProfile")
        print("👤 auth uid =", auth.currentUser?.uid ?? "nil")
        print("👤 auth email =", auth.currentUser?.email ?? "nil")
        print("👤 pseudo =", pseudo)
        print("👤 has imageData =", imageData != nil)
        print("👤 profileIcon =", profileIcon ?? "nil")

        var uploadedURL: String?

        if let imageData, let uid = auth.currentUser?.uid {
            print("🖼 image byteCount =", imageData.count)
            let compressed = normalizedProfileImageData(from: imageData) ?? imageData
            let filename = "profile_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"

            do {
                let uploaded = try await transferService.uploadProfileImage(
                    uid: uid,
                    imageData: compressed,
                    filename: filename
                )
                uploadedURL = uploaded.downloadURL
                print("✅ uploadProfileImage ok bucket = \(uploaded.bucket) path = \(uploaded.storagePath)")
            } catch {
                debugLog("UserRepository.updateProfile uploadProfileImage failed", error)
                throw error
            }
        }

        do {
            try await upsertProfile(pseudo: pseudo, photoURL: uploadedURL, profileIcon: profileIcon)
            print("✅ upsertProfile ok")
        } catch {
            debugLog("UserRepository.updateProfile upsertProfile failed", error)
            throw error
        }

        do {
            try await propagateProfileToCommunityMemberships(
                pseudo: pseudo,
                photoURL: uploadedURL,
                profileIcon: profileIcon
            )
            print("✅ propagateProfileToCommunityMemberships ok")
        } catch {
            debugLog("UserRepository.updateProfile propagateProfileToCommunityMemberships failed", error)
        }
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
}

final class CommunityRepository {
    private let auth = Auth.auth()
    var currentUID: String { auth.currentUser?.uid ?? "" }
    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west1")
    private let videoTransfer = VideoTransferService()

    private var communities: CollectionReference { db.collection("communities") }
    private var users: CollectionReference { db.collection("users") }

    func inviteLink(for communityId: String) -> String {
        "https://torpille-38783.web.app/join?cid=\(communityId)"
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
        let doc = communities.document()
        let community = Community(
            id: doc.documentID,
            name: name,
            isPublic: isPublic,
            adminUid: uid,
            responseTimeSeconds: responseTimeSeconds,
            createdAt: Timestamp(date: Date())
        )
        try doc.setData(from: community)
        let member = Member(uid: uid, pseudo: me.pseudo, photoUrl: nil, profileIcon: nil, xpInCommunity: 0)
        try doc.collection("members").document(uid).setData(from: member)
        return doc.documentID
    }

    func joinCommunity(communityId: String, me: UserProfile) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let member = Member(uid: uid, pseudo: me.pseudo, photoUrl: nil, profileIcon: nil, xpInCommunity: 0)
        try communities.document(communityId).collection("members").document(uid).setData(from: member, merge: true)
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

    func observeCommunity(_ communityId: String, handler: @escaping (Community?) -> Void) -> ListenerRegistration {
        communities.document(communityId).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists else {
                handler(nil)
                return
            }
            handler(try? snapshot.data(as: Community.self))
        }
    }

    func observeCommunitiesForMe(handler: @escaping ([Community]) -> Void) -> ListenerRegistration? {
        guard let uid = auth.currentUser?.uid else {
            handler([])
            return nil
        }

        return db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                Task {
                    let refs = snapshot?.documents.compactMap { $0.reference.parent.parent } ?? []
                    var result: [Community] = []
                    for ref in refs {
                        let snapshot = try? await ref.getDocument()
                        if let snapshot, snapshot.exists,
                           let community = try? snapshot.data(as: Community.self) {
                            result.append(community)
                        }
                    }
                    handler(result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                }
            }
    }

    func myCommunityIds() async throws -> [String] {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }

        let snapshot = try await db.collectionGroup("members")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()

        let ids = snapshot.documents.compactMap { $0.reference.parent.parent?.documentID }
        return Array(Set(ids)).sorted()
    }

    func observeMembers(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        communities.document(communityId)
            .collection("members")
            .order(by: "xpInCommunity", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else {
                    handler([])
                    return
                }

                let values = snapshot?.documents.compactMap { try? $0.data(as: Member.self) } ?? []
                Task {
                    let enriched = await self.enrichMembersWithUserProfiles(values)
                    handler(enriched)
                }
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
                return member
            }

            var updatedMember = member
            updatedMember.photoUrl = profile.photoUrl
            updatedMember.profileIcon = profile.profileIcon
            if !profile.pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedMember.pseudo = profile.pseudo
            }
            return updatedMember
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
                      let member = try? snapshot.data(as: Member.self) else {
                    handler(nil)
                    return
                }
                Task {
                    let enriched = await self.enrichMembersWithUserProfiles([member]).first
                    handler(enriched)
                }
            }
    }

    func observeMessages(_ communityId: String, handler: @escaping ([Message]) -> Void) -> ListenerRegistration {
        communities.document(communityId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { doc -> Message? in
                    var value = try? doc.data(as: Message.self)
                    value?.id = doc.documentID
                    return value
                } ?? []
                handler(values)
            }
    }

    func sendText(communityId: String, senderPseudo: String, text: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
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
            "createdAt": Timestamp(date: Date())
        ]

        _ = try await communities.document(communityId).collection("messages").addDocument(data: payload)
    }

    func observeRecentTorpilles(_ communityId: String, handler: @escaping ([Torpille]) -> Void) -> ListenerRegistration {
        communities.document(communityId)
            .collection("torpilles")
            .order(by: "createdAt", descending: true)
            .limit(to: 40)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { doc -> Torpille? in
                    var value = try? doc.data(as: Torpille.self)
                    value?.id = doc.documentID
                    return value
                } ?? []
                handler(values)
            }
    }

    func markTorpillesSeen(communityId: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        try await communities.document(communityId).collection("members").document(uid).setData([
            "lastSeenTorpilleAt": Timestamp(date: Date())
        ], merge: true)
    }

    func sendAudioMessage(communityId: String, senderPseudo: String, localFileURL: URL, durationSeconds: Double) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }

        print("📍 CommunityRepository.sendAudioMessage")
        print("🔐 auth.currentUser =", auth.currentUser?.uid ?? "nil")
        print("🔐 auth email =", auth.currentUser?.email ?? "nil")

        do {
            let token = try await auth.currentUser?.getIDTokenResult(forcingRefresh: true)
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
            "audioDurationSeconds": uploaded.durationSeconds,
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

    func sendVideoTorpille(
        communityId: String,
        senderPseudo: String,
        localFileURL: URL,
        taggedUid: String,
        taggedPseudo: String,
        tagX: Double,
        tagY: Double
    ) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }

        print("🔐 currentUser.uid =", uid)
        print("🔐 currentUser.email =", auth.currentUser?.email ?? "nil")

        do {
            if let token = try await auth.currentUser?.getIDTokenResult(forcingRefresh: true) {
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
        let community = try await getCommunityOrThrow(communityId)

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

        let createdAt = Timestamp(date: Date())
        let deadlineAt = Timestamp(date: Date().addingTimeInterval(TimeInterval(community.responseTimeSeconds)))
        let torpDoc = communities.document(communityId).collection("torpilles").document()
        let msgDoc = communities.document(communityId).collection("messages").document()

        let batch = db.batch()

        try batch.setData(from: Torpille(
            id: torpDoc.documentID,
            fromUid: uid,
            toUid: taggedUid,
            communityId: communityId,
            videoBucket: uploaded.bucket,
            videoPath: uploaded.storagePath,
            taggedPseudo: taggedPseudo,
            tagX: tagX,
            tagY: tagY,
            createdAt: createdAt,
            deadlineAt: deadlineAt,
            responded: false
        ), forDocument: torpDoc)

        try batch.setData(from: Message(
            id: msgDoc.documentID,
            type: "video",
            senderUid: uid,
            senderPseudo: senderPseudo,
            text: nil,
            videoUrl: nil,
            videoBucket: uploaded.bucket,
            videoPath: uploaded.storagePath,
            audioUrl: nil,
            audioBucket: nil,
            audioPath: nil,
            audioDurationSeconds: nil,
            imageUrl: nil,
            imageBucket: nil,
            imagePath: nil,
            taggedUid: taggedUid,
            taggedPseudo: taggedPseudo,
            tagX: tagX,
            tagY: tagY,
            torpilleId: torpDoc.documentID,
            createdAt: createdAt
        ), forDocument: msgDoc)

        batch.setData([
            "pendingTorpilleId": torpDoc.documentID,
            "pendingDeadlineAt": deadlineAt,
            "pendingFromPseudo": senderPseudo,
            "lastTorpilledAt": createdAt
        ], forDocument: communities.document(communityId).collection("members").document(taggedUid), merge: true)

        batch.setData([
            "uid": uid,
            "pseudo": senderPseudo,
            "xpInCommunity": FieldValue.increment(Int64(10))
        ], forDocument: communities.document(communityId).collection("members").document(uid), merge: true)

        print("📍 3. batch.commit")
        do {
            try await batch.commit()
            print("✅ batch.commit ok")
        } catch {
            let nsError = error as NSError
            print("🔥 batch.commit failed")
            print("domain =", nsError.domain)
            print("code =", nsError.code)
            print("userInfo =", nsError.userInfo)
            throw error
        }

        print("📍 4. sendTorpilleNotification")
        do {
            _ = try await functions.httpsCallable("sendTorpilleNotification").call([
                "toUid": taggedUid,
                "fromPseudo": senderPseudo,
                "communityName": community.name,
                "communityId": communityId
            ])
            print("✅ sendTorpilleNotification ok")
        } catch {
            let nsError = error as NSError
            print("⚠️ sendTorpilleNotification failed but torpille already saved")
            print("domain =", nsError.domain)
            print("code =", nsError.code)
            print("userInfo =", nsError.userInfo)
        }
    }

    func respondWithVideo(
        communityId: String,
        senderPseudo: String,
        localFileURL: URL,
        pendingTorpilleId: String,
        nextTaggedUid: String,
        nextTaggedPseudo: String,
        tagX: Double,
        tagY: Double
    ) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let torpRef = communities.document(communityId).collection("torpilles").document(pendingTorpilleId)
        let torpSnapshot = try await torpRef.getDocument()
        guard torpSnapshot.exists else {
            throw TorpilleError.missingData("Torpille introuvable")
        }
        let torp = try torpSnapshot.data(as: Torpille.self)
        guard torp.toUid == uid else {
            throw TorpilleError.missingData("Cette torpille ne t'est pas destinée")
        }

        print("📍 CommunityRepository.respondWithVideo")
        print("🎥 response localFileURL =", localFileURL.path)
        print("🎥 response file exists =", FileManager.default.fileExists(atPath: localFileURL.path))
        let now = Timestamp(date: Date())
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
            "xpInCommunity": FieldValue.increment(Int64(15))
        ], forDocument: communities.document(communityId).collection("members").document(uid))
        do {
            try await batch.commit()
            print("✅ respondWithVideo pre-batch commit ok")
        } catch {
            debugLog("CommunityRepository.respondWithVideo pre-batch commit failed", error)
            throw error
        }

        try await sendVideoTorpille(
            communityId: communityId,
            senderPseudo: senderPseudo,
            localFileURL: localFileURL,
            taggedUid: nextTaggedUid,
            taggedPseudo: nextTaggedPseudo,
            tagX: tagX,
            tagY: tagY
        )

        do {
            try await communities.document(communityId).collection("messages").addDocument(data: [
                "type": "text",
                "senderUid": uid,
                "senderPseudo": senderPseudo,
                "text": "a répondu à une torpille et a relancé !",
                "createdAt": now
            ])
            print("✅ respondWithVideo text message addDocument ok")
        } catch {
            debugLog("CommunityRepository.respondWithVideo text addDocument failed", error)
            throw error
        }
    }

    func updateMyLocation(in communityIds: [String], latitude: Double, longitude: Double) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let now = Timestamp(date: Date())
        for communityId in communityIds where !communityId.isEmpty {
            try await communities.document(communityId)
                .collection("members")
                .document(uid)
                .setData([
                    "lastLatitude": latitude,
                    "lastLongitude": longitude,
                    "lastLocationUpdatedAt": now
                ], merge: true)
        }
    }

    func observeMembersForMap(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        observeMembers(communityId, handler: handler)
    }
}
    