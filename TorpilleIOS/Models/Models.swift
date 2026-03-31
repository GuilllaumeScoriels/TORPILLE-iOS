import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var documentId: String?
    var uid: String = ""
    var email: String?
    var pseudo: String = ""
    var pseudoKey: String = ""
    var photoUrl: String?
    var profileIcon: String?
    var xpTotal: Int64 = 0
    var fcmToken: String?
    var updatedAt: Timestamp?

    var id: String { uid.isEmpty ? (documentId ?? UUID().uuidString) : uid }
}

struct Community: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var name: String = ""
    var isPublic: Bool = true
    var adminUid: String = ""
    var responseTimeSeconds: Int64 = 3600
    var createdAt: Timestamp?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }
}

struct Member: Codable, Identifiable {
    @DocumentID var documentId: String?
    var uid: String = ""
    var pseudo: String = ""
    var photoUrl: String?
    var profileIcon: String?
    var xpInCommunity: Int64 = 0
    var pendingTorpilleId: String?
    var pendingDeadlineAt: Timestamp?
    var pendingFromPseudo: String?
    var lastTorpilledAt: Timestamp?
    var lastRespondedAt: Timestamp?
    var overdueCount: Int64 = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationUpdatedAt: Timestamp?
    var lastSeenTorpilleAt: Timestamp?

    var id: String { uid.isEmpty ? (documentId ?? UUID().uuidString) : uid }
}

struct Message: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var type: String = "text"
    var senderUid: String = ""
    var senderPseudo: String = ""
    var text: String?
    var videoUrl: String?
    var videoBucket: String?
    var videoPath: String?
    var audioUrl: String?
    var audioBucket: String?
    var audioPath: String?
    var audioDurationSeconds: Double?
    var imageUrl: String?
    var imageBucket: String?
    var imagePath: String?
    var taggedUid: String?
    var taggedPseudo: String?
    var tagX: Double?
    var tagY: Double?
    var torpilleId: String?
    var createdAt: Timestamp?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }
}

struct Torpille: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var fromUid: String = ""
    var toUid: String = ""
    var communityId: String = ""
    var videoUrl: String?
    var videoBucket: String?
    var videoPath: String?
    var taggedPseudo: String?
    var tagX: Double?
    var tagY: Double?
    var createdAt: Timestamp?
    var deadlineAt: Timestamp?
    var responded: Bool = false
    var respondedAt: Timestamp?
    var nextToUid: String?
    var penaltyApplied: Bool = false

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }
}

struct UploadedVideo {
    let bucket: String
    let storagePath: String
}

struct UploadedAudio {
    let bucket: String
    let storagePath: String
    let durationSeconds: Double
}

struct UploadedImage {
    let bucket: String
    let storagePath: String
    let downloadURL: String
}

struct SignedURLResponse: Codable {
    let signedUrl: String
}

struct MapMemberAnnotation: Identifiable {
    let id: String
    let pseudo: String
    let latitude: Double
    let longitude: Double
    let subtitle: String
    let photoUrl: String?
    let profileIcon: String?
    let lastTorpilleTimeText: String
}
