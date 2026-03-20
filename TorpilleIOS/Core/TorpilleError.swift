/**
 Fichier : TorpilleError.swift
 Rôle :
 - Centralise les erreurs métier les plus fréquentes pour éviter de disperser
   des chaînes en dur dans toute l'application.

 Ce que fait ce fichier :
 - Définit les erreurs liées à l'authentification, aux données manquantes,
   aux pseudos invalides et aux vidéos non résolues.
 - Donne un message lisible côté interface via `errorDescription`.

 Pourquoi c'est utile :
 - L'UI SwiftUI peut afficher directement des messages cohérents.
 - Les repositories et view models restent plus propres.
 */

import Foundation

enum TorpilleError: LocalizedError {
    case notAuthenticated
    case missingData(String)
    case invalidPseudo
    case invalidResponseTime
    case videoNotAvailable
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Utilisateur non connecté."
        case .missingData(let message):
            return message
        case .invalidPseudo:
            return "Le pseudo doit contenir entre 3 et 20 caractères et n'utiliser que des lettres, chiffres, _ ou ."
        case .invalidResponseTime:
            return "Le temps de réponse doit être un nombre entier positif."
        case .videoNotAvailable:
            return "Impossible de lire cette vidéo pour le moment."
        case .locationUnavailable:
            return "Position indisponible. Vérifie les autorisations de localisation."
        }
    }
}
