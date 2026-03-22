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
        lastTorpilledAt?.formattedHourMinute ?? "--:--"
    }
}
