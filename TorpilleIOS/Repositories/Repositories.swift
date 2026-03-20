/**
 Fichier : Repositories.swift
 Rôle :
 - Implémente l'accès aux données Firebase pour l'application iOS.

 Ce que fait ce fichier :
 - Gère l'authentification, le profil, les communautés, les membres, les messages,
   l'upload vidéo et la carte.
 - Reprend les comportements importants de la version Android améliorée :
   création de torpilles vidéo, réponse vidéo, récupération d'URL signée,
   mise à jour de position et listes en temps réel.

 À noter :
 - Les listeners Firestore sont exposés avec des callbacks pour rester simples.
 - Le projet reste source-compatible avec XcodeGen et Firebase SPM.
 */

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

final class AuthRepository {
    private let auth = Auth.auth()

    var currentUID: String? { auth.currentUser?.uid }

    func signUp(email: String, password: String) async throws {
        _ = try await auth.createUser(withEmail: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        _ = try await auth.signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try auth.signOut()
    }
}

final class UserRepository {
    private let auth = Auth.auth()
    private let db = Firestore.firestore()

    private var users: CollectionReference { db.collection("users") }
    private var pseudos: CollectionReference { db.collection("pseudos") }

    func getMeOrThrow() async throws -> UserProfile {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let snapshot = try await users.document(uid).getDocument()
        guard snapshot.exists else {
            throw TorpilleError.missingData("Profil introuvable")
        }
        return try snapshot.data(as: UserProfile.self)
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
            handler(try? snapshot.data(as: UserProfile.self))
        }
    }

    func upsertProfile(pseudo: String, photoURL: String?) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let clean = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, clean.count <= 20,
              clean.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else {
            throw TorpilleError.invalidPseudo
        }

        let pseudoKey = clean.normalizedPseudoKey
        let userRef = users.document(uid)
        let pseudoRef = pseudos.document(pseudoKey)

        try await db.runTransaction { transaction, _ in
            let userSnapshot: DocumentSnapshot
            let pseudoSnapshot: DocumentSnapshot
            do {
                userSnapshot = try transaction.getDocument(userRef)
                pseudoSnapshot = try transaction.getDocument(pseudoRef)
            } catch {
                return nil
            }

            let currentKey = userSnapshot.data()?["pseudoKey"] as? String ?? ""
            if pseudoSnapshot.exists,
               let owner = pseudoSnapshot.data()?["uid"] as? String,
               owner != uid {
                return nil
            }

            transaction.setData([
                "uid": uid,
                "createdAt": Timestamp(date: Date())
            ], forDocument: pseudoRef, merge: true)

            var payload: [String: Any] = [
                "uid": uid,
                "pseudo": clean,
                "pseudoKey": pseudoKey,
                "updatedAt": Timestamp(date: Date())
            ]
            payload["photoUrl"] = photoURL?.isEmpty == false ? photoURL! : "https://api.dicebear.com/9.x/thumbs/png?seed=\(clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean)"
            transaction.setData(payload, forDocument: userRef, merge: true)

            if !currentKey.isEmpty, currentKey != pseudoKey {
                transaction.deleteDocument(self.pseudos.document(currentKey))
            }
            return nil
        }
    }
}

final class CommunityRepository {
    private let auth = Auth.auth()
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
        let member = Member(uid: uid, pseudo: me.pseudo, photoUrl: me.photoUrl, xpInCommunity: 0)
        try doc.collection("members").document(uid).setData(from: member)
        return doc.documentID
    }

    func joinCommunity(communityId: String, me: UserProfile) async throws {
        guard let uid = auth.currentUser?.uid else { throw TorpilleError.notAuthenticated }
        let member = Member(uid: uid, pseudo: me.pseudo, photoUrl: me.photoUrl, xpInCommunity: 0)
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

    func observeMembers(_ communityId: String, handler: @escaping ([Member]) -> Void) -> ListenerRegistration {
        communities.document(communityId)
            .collection("members")
            .order(by: "xpInCommunity", descending: true)
            .addSnapshotListener { snapshot, _ in
                let values = snapshot?.documents.compactMap { try? $0.data(as: Member.self) } ?? []
                handler(values)
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
            .addSnapshotListener { snapshot, _ in
                guard let snapshot, snapshot.exists else {
                    handler(nil)
                    return
                }
                handler(try? snapshot.data(as: Member.self))
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
        let payload: [String: Any] = [
            "type": "text",
            "senderUid": uid,
            "senderPseudo": senderPseudo,
            "text": text,
            "createdAt": Timestamp(date: Date())
        ]
        _ = try await communities.document(communityId).collection("messages").addDocument(data: payload)
    }

    func getSignedPlaybackURL(videoPath: String, videoBucket: String?) async throws -> URL {
        try await videoTransfer.resolvePlaybackURL(videoPath: videoPath, videoBucket: videoBucket)
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
        let community = try await getCommunityOrThrow(communityId)

        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))_\(uid).mp4"
        let uploaded = try await videoTransfer.uploadCommunityVideo(
            communityId: communityId,
            localFileURL: localFileURL,
            filename: filename
        )

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

        try await batch.commit()

        _ = try? await functions.httpsCallable("sendTorpilleNotification").call([
            "toUid": taggedUid,
            "fromPseudo": senderPseudo,
            "communityName": community.name,
            "communityId": communityId
        ])
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
        try await batch.commit()

        try await sendVideoTorpille(
            communityId: communityId,
            senderPseudo: senderPseudo,
            localFileURL: localFileURL,
            taggedUid: nextTaggedUid,
            taggedPseudo: nextTaggedPseudo,
            tagX: tagX,
            tagY: tagY
        )

        try await communities.document(communityId).collection("messages").addDocument(data: [
            "type": "text",
            "senderUid": uid,
            "senderPseudo": senderPseudo,
            "text": "a répondu à une torpille et a relancé !",
            "createdAt": now
        ])
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
