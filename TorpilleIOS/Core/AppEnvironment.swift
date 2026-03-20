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
 - Cette classe reste volontairement non isolée par acteur.
 - Cela évite les erreurs de compilation Swift Concurrency lors de la création
   de l'environnement au démarrage et lors de son injection dans les vues.
 */

import Foundation

final class AppEnvironment {
    lazy var authRepository = AuthRepository()
    lazy var userRepository = UserRepository()
    lazy var communityRepository = CommunityRepository()
    lazy var locationService = LocationService()
}
