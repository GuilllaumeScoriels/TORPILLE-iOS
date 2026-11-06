import Foundation
import FirebaseFirestore

enum ProfileSex: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case nonBinary = "non_binary"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .male: return "Homme"
        case .female: return "Femme"
        case .nonBinary: return "Non binaire"
        }
    }
}

struct UserProfile: Codable, Identifiable {
    @DocumentID var documentId: String?
    var uid: String = ""
    var email: String?
    var firstName: String = ""
    var lastName: String = ""
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
    var isGhostMode: Bool = false
    var friendsCount: Int = 0
    var birthDate: Timestamp?
    var sex: ProfileSex?
    var city: String?
    var bio: String?
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationUpdatedAt: Timestamp?
    var termsAcceptedAt: Timestamp?
    var moderationRulesAcceptedAt: Timestamp?
    var updatedAt: Timestamp?

    var id: String { uid.isEmpty ? (documentId ?? UUID().uuidString) : uid }
    var communityXPTotal: Int64 { communityXP.values.reduce(0, +) }
    var effectiveTotalXP: Int64 { communityXP.isEmpty ? xpTotal : communityXPTotal }

    var hasRequiredIdentity: Bool {
        let hasPseudo = !pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLegalName = !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAvatar = photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || profileIcon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasLegalName && hasPseudo && hasAvatar && termsAcceptedAt != nil && moderationRulesAcceptedAt != nil
    }

    var missingRequiredProfileFields: [String] {
        var fields: [String] = []
        if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("prénom") }
        if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("nom") }
        if pseudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("pseudo") }
        if photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           profileIcon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { fields.append("avatar") }
        if termsAcceptedAt == nil || moderationRulesAcceptedAt == nil { fields.append("acceptation des règles") }
        return fields
    }
}

struct Community: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var name: String = ""
    var isPublic: Bool = true
    var adminUid: String = ""
    var rankingSchedule: RankingSchedule?
    var eliminationMode: Bool?
    var responseTimeSeconds: Int64 = 3600
    var createdAt: Timestamp?

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }
}

enum CommunityJoinRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

struct CommunityJoinRequest: Codable, Identifiable {
    @DocumentID var documentId: String?
    var communityId: String = ""
    var communityName: String = ""
    var requesterUid: String = ""
    var requesterPseudo: String = ""
    var requesterPhotoUrl: String?
    var requesterProfileIcon: String?
    var adminUid: String = ""
    var status: String = CommunityJoinRequestStatus.pending.rawValue
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
    var resolvedAt: Timestamp?
    var reminderSentAt: Timestamp?

    var id: String { documentId ?? "\(communityId)_\(requesterUid)" }
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
    var lastTorpilleSentAt: Timestamp?
    var lastRespondedAt: Timestamp?
    var overdueCount: Int64 = 0
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationUpdatedAt: Timestamp?
    var lastSeenTorpilleAt: Timestamp?
    var lastSeenMessageAt: Timestamp?
    var lastOpenedAt: Timestamp?
    var lastActiveAt: Timestamp?

    var id: String { uid.isEmpty ? (documentId ?? UUID().uuidString) : uid }
}

/// Emojis members can react with. Must stay identical to the list in firestore.rules
/// (isValidMessageReactionUpdate).
enum MessageReaction {
    static let allowed = ["👍", "❤️", "😂", "😮", "😢", "🔥"]
}

struct MessageReactionCount: Hashable {
    let emoji: String
    let count: Int
}

struct Message: Codable, Identifiable {
    @DocumentID var documentId: String?
    var id: String?
    var systemEvent: String?
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
    /// Emoji reactions, one per member: uid -> emoji (see MessageReaction.allowed).
    var reactions: [String: String]? = nil

    var stableId: String {
        if let id, !id.isEmpty {
            return id
        }
        return documentId ?? UUID().uuidString
    }

    var isSaved: Bool {
        savedAt != nil
    }

    /// Reaction counts in the fixed display order, ignoring unknown values.
    var reactionSummary: [MessageReactionCount] {
        let values = Array((reactions ?? [:]).values)
        return MessageReaction.allowed.compactMap { emoji in
            let count = values.filter { $0 == emoji }.count
            return count > 0 ? MessageReactionCount(emoji: emoji, count: count) : nil
        }
    }

    func reaction(of uid: String?) -> String? {
        guard let uid, !uid.isEmpty, let value = reactions?[uid],
              MessageReaction.allowed.contains(value) else { return nil }
        return value
    }

    var isQuarantined: Bool {
        moderationStatus != nil && moderationStatus != "visible"
    }
}

struct Torpille: Codable, Identifiable {
    var responseRequired: Bool?
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
        moderationStatus != nil && moderationStatus != "visible"
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
        moderationStatus != nil && moderationStatus != "visible"
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
        case authorPhotoUrl
        case authorProfileIcon
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
    let downloadURL: String
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

struct MapMemberAnnotation: Identifiable, Equatable {
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
    var mode: CommunityNotificationMode = .all
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

struct FriendRemoval: Codable, Identifiable {
    @DocumentID var documentId: String?
    var actorUid: String = ""
    var actorPseudo: String = ""
    var toUid: String = ""
    var type: String = "friendRemoved"
    var createdAt: Timestamp?

    var id: String { documentId ?? UUID().uuidString }
}


struct HomeAnnouncement: Identifiable {
    let id: String
    let title: String
    let body: String
    let imageUrls: [URL]
    let priority: Int

    init?(id: String, data: [String: Any]) {
        guard data["published"] as? Bool == true else { return nil }
        self.id = id
        title = String(((data["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        body = String(((data["body"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000))
        var seen = Set<String>()
        imageUrls = Array(((data["imageUrls"] as? [Any]) ?? []).compactMap { $0 as? String }
            .compactMap { value -> URL? in
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: clean), url.scheme == "https", let host = url.host, !host.isEmpty,
                      seen.insert(clean).inserted else { return nil }
                return url
            }.prefix(5))
        priority = (data["priority"] as? NSNumber)?.intValue ?? 0
        guard !title.isEmpty || !body.isEmpty || !imageUrls.isEmpty else { return nil }
    }
}

struct WeeklyRankingWindow: Codable, Equatable {
    var day: Int = 1 // ISO weekday: Monday = 1, Sunday = 7
    var startMinute: Int = 540
    var endMinute: Int = 1320
}

// A weekly clock time is not an instant on today's date: using today's local
// midnight shifts the picker by an hour on daylight-saving transitions.
enum RankingClockTime {
    static let timeZone = TimeZone(secondsFromGMT: 0)!
    static func date(minutes: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(minutes * 60))
    }
    static func minutes(in date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
struct DatedRankingWindow: Codable, Equatable {
    var startMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var endMs: Int64 = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)
}
struct RankingSchedule: Codable, Equatable {
    var fullTime = true
    var timeZone = TimeZone.current.identifier
    var weekly: [WeeklyRankingWindow] = []
    var dates: [DatedRankingWindow] = []
    func isActive(at date: Date = Date()) -> Bool {
        if fullTime { return true }
        let ms = Int64(date.timeIntervalSince1970 * 1000)
        if dates.contains(where: { ms >= $0.startMs && ms < $0.endMs }) { return true }
        guard let zone = TimeZone(identifier: timeZone) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return weekly.contains { window in
            if window.startMinute < window.endMinute {
                return day == window.day && minute >= window.startMinute && minute < window.endMinute
            }
            return (day == window.day && minute >= window.startMinute) || (day == window.day % 7 + 1 && minute < window.endMinute)
        }
    }
    var payload: [String: Any] {
        ["fullTime": fullTime, "timeZone": timeZone,
         "weekly": weekly.map { ["day": $0.day, "startMinute": $0.startMinute, "endMinute": $0.endMinute] },
         "dates": dates.map { ["startMs": $0.startMs, "endMs": $0.endMs] }]
    }
}
