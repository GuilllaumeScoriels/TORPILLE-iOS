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
    var communityIds: [String] = []
    var pinnedCommunityIds: [String] = []
    var communityXP: [String: Int64] = [:]
    var xpTotal: Int64 = 0
    var fcmToken: String?
    var languageCode: String?
    var isLanguagePublic: Bool = true
    var isLeaderboardPublic: Bool = true
    var friendsCount: Int = 0
    var termsAcceptedAt: Timestamp?
    var moderationRulesAcceptedAt: Timestamp?
    var updatedAt: Timestamp?

    var id: String { uid.isEmpty ? (documentId ?? UUID().uuidString) : uid }
    var communityXPTotal: Int64 { communityXP.values.reduce(0, +) }
    var effectiveTotalXP: Int64 { communityXP.isEmpty ? xpTotal : communityXPTotal }

    var hasRequiredIdentity: Bool {
        let hasPseudo = !pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAvatar = photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || profileIcon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasPseudo && hasAvatar && termsAcceptedAt != nil && moderationRulesAcceptedAt != nil
    }
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
    var lastSeenMessageAt: Timestamp?
    var lastOpenedAt: Timestamp?

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
    var savedAt: Timestamp?
    var savedByUid: String?
    var savedByPseudo: String?
    var moderationStatus: String?
    var reportCount: Int64?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }

    var isSaved: Bool {
        savedAt != nil
    }

    var isQuarantined: Bool {
        moderationStatus == "quarantined" || moderationStatus == "removed"
    }
}

struct Torpille: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var fromUid: String = ""
    var fromPseudo: String?
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
    var isPublished: Bool = false
    var publishedAt: Timestamp?
    var publishedByUid: String?
    var publishedByPseudo: String?
    var communityName: String?
    var moderationStatus: String?
    var reportCount: Int64?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }

    var isQuarantined: Bool {
        moderationStatus == "quarantined" || moderationStatus == "removed"
    }
}

struct PublishedReel: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var torpilleId: String = ""
    var sourceMessageId: String?
    var communityId: String = ""
    var communityName: String = ""
    var authorUid: String = ""
    var authorPseudo: String = ""
    var authorPhotoUrl: String?
    var authorProfileIcon: String?
    var videoUrl: String?
    var videoBucket: String?
    var videoPath: String?
    var taggedPseudo: String?
    var createdAt: Timestamp?
    var publishedAt: Timestamp?
    var moderationStatus: String?
    var reportCount: Int64?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }

    var isQuarantined: Bool {
        moderationStatus == "quarantined" || moderationStatus == "removed"
    }

    enum CodingKeys: String, CodingKey {
        case documentId
        case id
        case torpilleId
        case sourceMessageId
        case communityId
        case communityName
        case authorUid
        case authorPseudo
        case videoUrl
        case videoBucket
        case videoPath
        case taggedPseudo
        case createdAt
        case publishedAt
        case moderationStatus
        case reportCount
    }
}

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case harassment
    case sexualContent
    case violenceThreat
    case hateSpeech
    case spam
    case unwantedContent
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: return "Harcèlement"
        case .sexualContent: return "Contenu sexuel"
        case .violenceThreat: return "Violence ou menace"
        case .hateSpeech: return "Discours haineux"
        case .spam: return "Spam"
        case .unwantedContent: return "Contenu non désiré"
        case .other: return "Autre"
        }
    }
}

enum ReportedContentType: String, Codable {
    case message
    case torpille
    case reel
    case profile
}

struct BlockedUser: Codable, Identifiable {
    @DocumentID var documentId: String?
    var blockedUid: String = ""
    var pseudo: String = ""
    var photoUrl: String?
    var profileIcon: String?
    var createdAt: Timestamp?

    var id: String { blockedUid.isEmpty ? (documentId ?? UUID().uuidString) : blockedUid }
}

struct UploadedVideo {
    let bucket: String
    let storagePath: String
    let downloadURL: String
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


enum CommunityNotificationMode: String, Codable, CaseIterable, Identifiable {
    case all
    case mentionsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Tout"
        case .mentionsOnly:
            return "Seulement moi"
        }
    }
}

struct CommunityNotificationPreference: Codable, Identifiable {
    var communityId: String
    var communityName: String
    var mode: CommunityNotificationMode = .mentionsOnly
    var updatedAt: Timestamp?

    var id: String { communityId }
}

struct AppNotificationItem: Codable, Identifiable, Equatable {
    var id: String
    var communityId: String
    var communityName: String
    var title: String
    var body: String
    var createdAt: Date = Date()
    var isRead: Bool = false
    var deepLink: String = "notificationCenter"
}

struct PublicFriend: Codable, Identifiable {
    @DocumentID var documentId: String?
    var uid: String = ""
    var pseudo: String = ""
    var photoUrl: String?
    var profileIcon: String?
    var createdAt: Timestamp?

    var id: String { uid.isEmpty ? (documentId ?? UUID().uuidString) : uid }
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

struct FriendRequest: Codable, Identifiable {
    @DocumentID var documentId: String?
    var fromUid: String = ""
    var fromPseudo: String = ""
    var fromPhotoUrl: String?
    var fromProfileIcon: String?
    var toUid: String = ""
    var toPseudo: String = ""
    var status: String = FriendRequestStatus.pending.rawValue
    var createdAt: Timestamp?
    var updatedAt: Timestamp?

    var id: String { documentId ?? "\(fromUid)_\(toUid)" }
}
