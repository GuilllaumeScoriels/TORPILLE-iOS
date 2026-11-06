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
    case pseudoAlreadyUsed
    case invalidResponseTime
    case videoNotAvailable
    case locationUnavailable
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Utilisateur non connecté."
        case .missingData(let message):
            return message
        case .invalidPseudo:
            return "Le pseudo doit contenir entre 3 et 20 caractères et n'utiliser que des lettres, chiffres, _ ou ."
        case .pseudoAlreadyUsed:
            return "Ce pseudo est déjà utilisé par un autre utilisateur. Choisis un autre pseudo pour continuer."
        case .invalidResponseTime:
            return "Le temps de réponse doit être un nombre entier positif."
        case .videoNotAvailable:
            return "Impossible de lire cette vidéo pour le moment."
        case .locationUnavailable:
            return "Position indisponible. Vérifie les autorisations de localisation."
        case .uploadFailed(let message):
            return message
        }
    }
}

/// The only boundary for errors presented to users. SDK descriptions and
/// server details are diagnostic data, never displayable copy.
enum UserFacingError {
    static let fallback = "Cette action n’a pas pu aboutir. Réessaie dans quelques instants."
    static let unavailable = "Ce service est momentanément indisponible. Réessaie plus tard."
    static let network = "Connexion indisponible. Vérifie ta connexion Internet puis réessaie."

    static func message(for error: Error) -> String {
        if let local = error as? TorpilleError {
            let text = local.errorDescription ?? fallback
            let technical = ["firebase", "firestore", "app check", "bucket", "userinfo", "nslocalized", "domain", "identitytoolkit", "étape:", "domaine:", "code:", "gs://"]
            return technical.contains(where: { text.localizedCaseInsensitiveContains($0) }) ? fallback : text
        }
        let error = error as NSError
        if error.domain == NSURLErrorDomain { return network }
        if error.domain == "UserRepository", error.code == 409 {
            return TorpilleError.pseudoAlreadyUsed.errorDescription!
        }
        if error.domain == "FIRAuthErrorDomain" {
            switch error.code {
            case 17008: return "Adresse email invalide. Vérifie le format, par exemple nom@example.com."
            case 17009, 17004: return "Email ou mot de passe incorrect."
            case 17011: return "Aucun compte ne correspond à cet email."
            case 17007: return "Cette adresse email est déjà utilisée. Connecte-toi ou réinitialise ton mot de passe."
            case 17026: return "Choisis un mot de passe d’au moins 6 caractères."
            case 17010, 17052: return "Trop de tentatives. Patiente avant de réessayer."
            case 17020: return network
            case 17014: return "Reconnecte-toi pour effectuer cette action."
            case 17005: return "Ce compte est désactivé. Contacte l’assistance."
            case 17042: return "Indique un numéro de téléphone valide avec son indicatif international."
            case 17044: return "Le code SMS est incorrect. Vérifie-le puis réessaie."
            case 17051: return "Le code SMS a expiré. Demande un nouveau code."
            case 17025: return "Ce numéro est déjà associé à un autre compte."
            default: return unavailable
            }
        }
        // FirebaseFunctions reports errors under FunctionsErrorDomain ("com.firebase.functions");
        // the legacy name is kept for older SDKs and existing tests.
        if error.domain == "com.firebase.functions" || error.domain == "FIRFunctionsErrorDomain" {
            // Only reviewed product messages may cross the server/UI boundary.
            let text = error.localizedDescription
            if serverMessages.contains(text) { return text }
            switch error.code {
            case 3: return "Vérifie les informations saisies puis réessaie."
            case 7: return "Tu ne peux pas effectuer cette action avec ce compte."
            case 8: return "La limite a été atteinte. Réessaie plus tard."
            case 16: return "Reconnecte-toi pour continuer."
            case 4, 13, 14, 5, 12: return unavailable
            default: return fallback
            }
        }
        if error.domain == "FIRFirestoreErrorDomain" {
            switch error.code {
            case 7: return "Cette action n’est pas autorisée avec ce compte."
            case 16: return "Reconnecte-toi pour continuer."
            case 4, 14: return network
            default: return fallback
            }
        }
        if error.domain == "FIRStorageErrorDomain" {
            switch error.code {
            case -13010: return "Ce contenu n’est plus disponible."
            case -13020: return "Reconnecte-toi pour envoyer ce contenu."
            case -13021: return "Tu n’as pas accès à ce contenu."
            case -13030: return "Le transfert a pris trop de temps. Vérifie ta connexion puis réessaie."
            default: return "Impossible de transférer ce contenu pour le moment. Réessaie."
            }
        }
        return fallback
    }

    private static let serverMessages: Set<String> = [
        "Les torpilles sont fermées à cet horaire. Tu peux seulement répondre à une torpille reçue.",
        "Attends la fin de l’envoi de la vidéo.",
        "Cette torpille ne peut plus recevoir de réponse.",
        "Cette torpille appartient à une ancienne adhésion.",
        "Délai dépassé : tu vas être expulsé de cette communauté.",
        "Réponds à ta torpille en cours avant d’en envoyer une autre.",
        "Tu es le dernier membre : supprime la communauté depuis ses paramètres.",
        "Seul l’administrateur peut modifier les paramètres.",
        "Paramètres invalides : délai de 1 seconde à 7 jours.",
        "Ajoute au moins un créneau ou une période.",
        "Créneau hebdomadaire invalide.", "Période datée invalide.", "Fuseau horaire invalide.",
        "Vérifie ton numéro par SMS avant de devenir visible.",
        "Vérifie ton numéro par SMS avant de rechercher des contacts.",
        "Limite quotidienne atteinte. Réessaie demain."
    ]
}

func userErrorMessage(_ error: Error) -> String {
    logDiagnostic(error)
    return UserFacingError.message(for: error)
}

func logDiagnostic(_ error: Error) {
    #if DEBUG
    let error = error as NSError
    print("[Diagnostic]", error.domain, error.code, error.userInfo)
    #endif
}
