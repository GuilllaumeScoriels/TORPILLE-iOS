/**
 Fichier : Extensions.swift
 Rôle :
 - Regroupe des helpers transverses utilisés par plusieurs écrans.

 Ce que fait ce fichier :
 - Normalise les pseudos comme côté Android.
 - Formate les dates pour la carte et les messages.
 - Donne des identifiants / comparateurs utiles pour SwiftUI.
 */

import Foundation
import FirebaseFirestore
import SwiftUI

enum AppExternalLinks {
    static func privacyPolicy(language: AppLanguage) -> URL {
        var components = URLComponents(string: "https://torpille-38783.web.app/privacy.html")!
        components.queryItems = [URLQueryItem(name: "lang", value: language.localeIdentifier)]
        return components.url!
    }
    static let support = URL(string: "https://torpille-38783.web.app/support.html")!
}

extension String {
    var normalizedPseudoKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Timestamp {
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: dateValue())
    }

    var formattedHourMinute: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: dateValue())
    }
}

extension Member {
    var displayName: String {
        let trimmed = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? uid : trimmed
    }

    var mapSubtitle: String {
        let torpilleText = lastTorpilledAt?.formattedDateTime ?? "jamais"
        let locationText = lastLocationUpdatedAt?.formattedDateTime ?? "jamais"
        return "Dernière torpille : \(torpilleText) • Position mise à jour : \(locationText)"
    }

    var mapLastTorpilleTimeText: String {
        guard let sentTimestamp = lastTorpilleSentAt else {
            return ""
        }

        let elapsedTime = Date().timeIntervalSince(sentTimestamp.dateValue())
        guard elapsedTime >= 0, elapsedTime < 24 * 60 * 60 else { return "" }
        return sentTimestamp.formattedHourMinute
    }
}

private struct IOSBackSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    guard isEnabled else { return }
                    let startedNearLeadingEdge = value.startLocation.x <= 32
                    let isHorizontalBackSwipe = value.translation.width >= 70
                        && abs(value.translation.height) <= 80
                    guard startedNearLeadingEdge && isHorizontalBackSwipe else { return }
                    action()
                }
        )
    }
}

extension View {
    func iosBackSwipe(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(IOSBackSwipeModifier(isEnabled: enabled, action: action))
    }
}
