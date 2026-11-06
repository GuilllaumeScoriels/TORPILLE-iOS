import XCTest
import FirebaseAuth
@testable import TorpilleIOS

final class HomeCommunityPresentationTests: XCTestCase {
    @MainActor
    func testManualMapCheckInExpiresWithoutRenewal() {
        let checkIn = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(MapViewModel.isCheckInVisible(checkIn, at: checkIn))
        XCTAssertTrue(MapViewModel.isCheckInVisible(checkIn, at: checkIn.addingTimeInterval(1799)))
        XCTAssertFalse(MapViewModel.isCheckInVisible(checkIn, at: checkIn.addingTimeInterval(1800)))
        XCTAssertFalse(MapViewModel.isCheckInVisible(checkIn, at: checkIn.addingTimeInterval(3600)))
        XCTAssertFalse(MapViewModel.isCheckInVisible(checkIn, at: checkIn.addingTimeInterval(-1)))
    }

    func testNormalizedCommunityIdsRemoveBlanksAndDuplicatesWhilePreservingOrder() {
        let result = CommunityMembershipStore.normalizedIDs(
            from: ["c1", " ", "c2", "c1", "", "c3", "c2"]
        )

        XCTAssertEqual(result, ["c1", "c2", "c3"])
    }

    func testNormalizedCommunityIdsCanBeLimited() {
        let result = CommunityMembershipStore.normalizedIDs(
            from: ["c1", "c2", "c3", "c4"],
            limit: 2
        )

        XCTAssertEqual(result, ["c1", "c2"])
    }

    func testMergedCommunityIdsPreservePrimaryOrderAndAppendMissingMemberships() {
        let result = CommunityMembershipStore.mergedIDs(
            primary: ["c2", "c1"],
            secondary: ["c1", "c3", "c4"]
        )

        XCTAssertEqual(result, ["c2", "c1", "c3", "c4"])
    }

    func testPinnedCommunitiesPreservePinnedOrderAndLimitToThree() {
        let communities = [
            makeCommunity(id: "c1", name: "One"),
            makeCommunity(id: "c2", name: "Two"),
            makeCommunity(id: "c3", name: "Three"),
            makeCommunity(id: "c4", name: "Four")
        ]

        let result = HomeCommunityPresentation.pinnedCommunities(
            from: communities,
            pinnedCommunityIds: ["c3", "c1", "c4", "c2"]
        )

        XCTAssertEqual(result.map(\.stableId), ["c3", "c1", "c4"])
    }

    func testHomeCommunitiesFallbackToMostRecentlyOpenedWhenNothingPinned() {
        let communities = [
            makeCommunity(id: "recent", name: "Recent"),
            makeCommunity(id: "older", name: "Older")
        ]

        let result = HomeCommunityPresentation.homeCommunities(
            from: communities,
            pinnedCommunityIds: []
        )

        XCTAssertEqual(result.map(\.stableId), ["recent"])
    }

    func testOrderedCommunitiesPlacePinnedFirstAndKeepRemainingOrder() {
        let communities = [
            makeCommunity(id: "recent", name: "Recent"),
            makeCommunity(id: "older", name: "Older"),
            makeCommunity(id: "oldest", name: "Oldest")
        ]

        let result = HomeCommunityPresentation.orderedCommunities(
            from: communities,
            pinnedCommunityIds: ["oldest", "recent"]
        )

        XCTAssertEqual(result.map(\.stableId), ["oldest", "recent", "older"])
    }

    func testLeaderboardXPUsesSelectedCommunityTotalsFromUserProfile() {
        let player = UserProfile(
            documentId: "u1",
            uid: "u1",
            email: nil,
            pseudo: "Alice",
            pseudoKey: "alice",
            photoUrl: nil,
            profileIcon: nil,
            communityIds: ["c1", "c2", "c3"],
            pinnedCommunityIds: [],
            communityXP: ["c1": 15, "c2": 40, "c3": 7],
            xpTotal: 120,
            fcmToken: nil,
            updatedAt: nil
        )

        XCTAssertEqual(
            LeaderboardXP.displayedXP(for: player, selectedCommunityIds: ["c1", "c3"]),
            22
        )
        XCTAssertEqual(
            LeaderboardXP.displayedXP(for: player, selectedCommunityIds: []),
            62
        )
    }

    private func makeCommunity(id: String, name: String) -> Community {
        Community(
            documentId: id,
            id: id,
            name: name,
            isPublic: true,
            adminUid: "user",
            responseTimeSeconds: 3600,
            createdAt: nil
        )
    }
}

final class LegalAcceptanceTests: XCTestCase {
    func testAccountAcceptancePersistsAndDoesNotAuthorizeAnotherAccount() {
        withIsolatedDefaults { defaults in
            let accepted = LegalAcceptanceDraft(acceptsEULA: true, acceptsPrivacyPolicy: true)
            XCTAssertTrue(DeviceLegalAcceptance.recordForAccount(accepted, uid: "account-a", in: defaults))
            XCTAssertTrue(DeviceLegalAcceptance.hasAcceptedCurrentVersion(for: "account-a", in: defaults))
            XCTAssertFalse(DeviceLegalAcceptance.hasAcceptedCurrentVersion(for: "account-b", in: defaults))
            XCTAssertFalse(DeviceLegalAcceptance.hasAcceptedCurrentVersion(for: nil, in: defaults))
            // An acceptance copied from a different device must not be reused.
            defaults.set("other-device", forKey: DeviceLegalAcceptance.eulaVersionKey + ".account.account-a")
            XCTAssertFalse(DeviceLegalAcceptance.hasAcceptedCurrentVersion(for: "account-a", in: defaults))
        }
    }

    func testOnlyBothExplicitAcceptancesUnlockContinuation() {
        for eula in [false, true] {
            for privacy in [false, true] {
                let draft = LegalAcceptanceDraft(acceptsEULA: eula, acceptsPrivacyPolicy: privacy)
                XCTAssertEqual(draft.canContinue, eula && privacy)
            }
        }
    }

    func testIncompleteAcceptanceCannotBePersisted() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(DeviceLegalAcceptance.record(LegalAcceptanceDraft(acceptsEULA: true), in: defaults))
            XCTAssertFalse(DeviceLegalAcceptance.record(LegalAcceptanceDraft(acceptsPrivacyPolicy: true), in: defaults))
            XCTAssertFalse(DeviceLegalAcceptance.hasAcceptedCurrentVersion(in: defaults))
            XCTAssertNil(defaults.string(forKey: DeviceLegalAcceptance.eulaVersionKey))
            XCTAssertNil(defaults.string(forKey: DeviceLegalAcceptance.privacyPolicyVersionKey))
        }
    }

    func testLegacyAppRulesAcceptanceDoesNotCountAsPrivacyAcceptance() {
        withIsolatedDefaults { defaults in
            defaults.set(DeviceLegalAcceptance.currentAcceptanceValue, forKey: DeviceLegalAcceptance.eulaVersionKey)
            defaults.set(DeviceLegalAcceptance.currentAcceptanceValue, forKey: "acceptedAppRulesVersion")
            XCTAssertFalse(DeviceLegalAcceptance.hasAcceptedCurrentVersion(in: defaults))
        }
    }

    func testBothAcceptancesPersistButNewConnectionStartsUnchecked() {
        withIsolatedDefaults { defaults in
            let accepted = LegalAcceptanceDraft(acceptsEULA: true, acceptsPrivacyPolicy: true)
            XCTAssertTrue(DeviceLegalAcceptance.record(accepted, in: defaults))
            XCTAssertTrue(DeviceLegalAcceptance.hasAcceptedCurrentVersion(in: defaults))
            XCTAssertFalse(LegalAcceptanceDraft().canContinue)
            defaults.set("old-version", forKey: DeviceLegalAcceptance.privacyPolicyVersionKey)
            XCTAssertFalse(DeviceLegalAcceptance.hasAcceptedCurrentVersion(in: defaults))
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "LegalAcceptanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}

final class PrivacyPolicyLinkTests: XCTestCase {
    func testEveryAppLanguageIsIncludedInThePrivacyPolicyLink() {
        let cases: [(AppLanguage, String)] = [(.french, "fr"), (.english, "en"), (.spanish, "es"), (.german, "de"), (.italian, "it"), (.portuguese, "pt"), (.system, "fr")]
        for (language, code) in cases {
            let url = AppExternalLinks.privacyPolicy(language: language)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            XCTAssertEqual(url.host, "torpille-38783.web.app")
            XCTAssertEqual(url.path, "/privacy.html")
            XCTAssertEqual(components?.queryItems, [URLQueryItem(name: "lang", value: code)])
        }
    }
}

final class HomeAnnouncementTests: XCTestCase {
    func testDraftAndEmptyAnnouncementsAreHidden() {
        XCTAssertNil(HomeAnnouncement(id: "draft", data: ["published": false, "title": "Draft"]))
        XCTAssertNil(HomeAnnouncement(id: "empty", data: ["published": true, "body": "  "]))
    }
    func testTextAndImagesAreDecodedAndUnsafeURLsIgnored() {
        let item = HomeAnnouncement(id: "news", data: ["published": true, "title": " News ",
            "body": "First\nSecond", "priority": 4,
            "imageUrls": ["https://example.com/a.jpg", "http://example.com/b.jpg", "file:///private/a", "https://example.com/a.jpg"]])
        XCTAssertEqual(item?.title, "News")
        XCTAssertEqual(item?.body, "First\nSecond")
        XCTAssertEqual(item?.imageUrls.map(\.absoluteString), ["https://example.com/a.jpg"])
        XCTAssertEqual(item?.priority, 4)
    }
    func testImageOnlyAnnouncementIsSupported() {
        XCTAssertNotNil(HomeAnnouncement(id: "photo", data: ["published": true, "imageUrls": ["https://example.com/a.jpg"]]))
    }
}

final class RankingScheduleTests: XCTestCase {
    func testWeeklyPickerClockRoundTripIsIndependentOfDeviceTimeZone() {
        for minute in [0, 120, 180, 540, 1439] {
            XCTAssertEqual(RankingClockTime.minutes(in: RankingClockTime.date(minutes: minute)), minute)
        }
        XCTAssertEqual(RankingClockTime.minutes(in: RankingClockTime.date(minutes: 1440)), 0)
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testWeeklyBoundariesAndCommunityTimeZone() {
        let schedule = RankingSchedule(fullTime: false, timeZone: "Europe/Brussels", weekly: [WeeklyRankingWindow(day: 1, startMinute: 540, endMinute: 1080)])
        XCTAssertFalse(schedule.isActive(at: date("2026-10-12T06:59:59Z")))
        XCTAssertTrue(schedule.isActive(at: date("2026-10-12T07:00:00Z")))
        XCTAssertFalse(schedule.isActive(at: date("2026-10-12T16:00:00Z")))
    }
    func testOvernightAndDatedUnion() {
        var schedule = RankingSchedule(fullTime: false, timeZone: "UTC", weekly: [WeeklyRankingWindow(day: 7, startMinute: 1320, endMinute: 120)])
        XCTAssertTrue(schedule.isActive(at: date("2026-10-12T01:59:59Z")))
        XCTAssertFalse(schedule.isActive(at: date("2026-10-12T02:00:00Z")))
        let start = Int64(date("2026-10-14T10:00:00Z").timeIntervalSince1970 * 1000)
        schedule.dates = [DatedRankingWindow(startMs: start, endMs: start + 3600000)]
        XCTAssertTrue(schedule.isActive(at: date("2026-10-14T10:00:00Z")))
        XCTAssertFalse(schedule.isActive(at: date("2026-10-14T11:00:00Z")))
    }
    func testRepeatedAutumnHourStaysWithinWeeklyWindow() {
        let schedule = RankingSchedule(fullTime: false, timeZone: "Europe/Brussels", weekly: [WeeklyRankingWindow(day: 7, startMinute: 120, endMinute: 180)])
        XCTAssertTrue(schedule.isActive(at: date("2026-10-25T00:30:00Z")))
        XCTAssertTrue(schedule.isActive(at: date("2026-10-25T01:30:00Z")))
    }
}

final class FirebaseLaunchRegressionTests: XCTestCase {
    @MainActor
    func testPhoneAuthNotificationManagerIsInitializedAfterAppLaunch() {
        // This public API force-unwraps the same phone-auth infrastructure that
        // crashed on device when Firebase was configured in SwiftUI App.init.
        // An unrelated payload does not send an SMS or change account data.
        XCTAssertFalse(Auth.auth().canHandleNotification(["audit": "unrelated-notification"]))
        XCTAssertFalse(Auth.auth().canHandle(URL(string: "torpille://join?cid=audit")!))
    }

    func testMessageReactionSummaryCountsAllowedEmojisInOrder() {
        var message = Message(documentId: nil)
        message.reactions = ["a": "🔥", "b": "👍", "c": "🔥", "d": "🍆", "e": ""]
        XCTAssertEqual(message.reactionSummary, [
            MessageReactionCount(emoji: "👍", count: 1),
            MessageReactionCount(emoji: "🔥", count: 2)
        ])
        XCTAssertEqual(message.reaction(of: "c"), "🔥")
        XCTAssertNil(message.reaction(of: "d"), "Unknown emojis are ignored")
        XCTAssertNil(message.reaction(of: nil))
        XCTAssertNil(message.reaction(of: ""))
        XCTAssertTrue(Message(documentId: nil).reactionSummary.isEmpty)
    }
}
