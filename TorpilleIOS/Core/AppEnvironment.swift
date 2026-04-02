/**
 Fichier : AppEnvironment.swift
 Rôle :
 - Assemble les dépendances partagées de l'application iOS.

 Ce que fait ce fichier :
 - Crée une seule fois les repositories et services Firebase / localisation.
 - Fournit un point d'injection simple aux view models et aux vues.

 Pourquoi c'est utile :
 - Évite de recréer les mêmes objets partout.
 - Simplifie le portage depuis l'architecture Android orientée repositories/viewmodels.

 Note de correction :
 - Cet environnement est isolé sur le MainActor car il expose aussi
   `NotificationCenterService`, lui-même annoté `@MainActor`.
 - Cela supprime l'erreur Swift Concurrency liée à l'initialisation paresseuse
   du service de notifications depuis un contexte non isolé.
 */

import Foundation

@MainActor
final class AppEnvironment {
    lazy var authRepository = AuthRepository()
    lazy var userRepository = UserRepository()
    lazy var communityRepository = CommunityRepository()
    lazy var locationService = LocationService()
    lazy var notificationCenterService = NotificationCenterService(communityRepository: communityRepository)
}
