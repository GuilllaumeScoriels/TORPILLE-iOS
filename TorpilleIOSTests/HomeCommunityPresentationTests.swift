import XCTest
@testable import TorpilleIOS

final class HomeCommunityPresentationTests: XCTestCase {
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
