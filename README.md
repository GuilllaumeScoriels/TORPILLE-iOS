# TORPILLE · iOS

Application sociale native en **Swift et SwiftUI** : communautés, messagerie multimédia et géolocalisation.

[Version Android](https://github.com/GuilllaumeScoriels/APK_TORPILLE) · [Fiche App Store](https://apps.apple.com/fr/app/torpille/id6761060711)

## Fonctionnalités

- Création et participation à des communautés.
- Messages texte et vidéo, envoi et réponse aux torpilles vidéo.
- Lecture vidéo native avec AVPlayer et affichage des tags.
- Carte des membres avec MapKit.
- Invitations et liens vers l’application via `torpille://`.

## Architecture

Architecture **MVVM avec repositories**, backend Firebase partagé avec Android.

| Dossier | Rôle |
| --- | --- |
| `TorpilleIOS/Core/` | Initialisation et utilitaires |
| `TorpilleIOS/Models/` | Modèles Firestore |
| `TorpilleIOS/Repositories/` | Firebase, médias, fonctions et localisation |
| `TorpilleIOS/ViewModels/` | Logique des écrans |
| `TorpilleIOS/Views/` | Écrans et composants SwiftUI |
| `TorpilleIOSTests/` | Tests du projet |
| `functions/` | Cloud Functions |
| `Hosting/` | Page web d’invitation |

**Technologies :** Swift, SwiftUI, Firebase, MapKit, AVKit, PhotosPicker, XcodeGen.

## Installation

1. Cloner le dépôt sur un Mac avec Xcode.
2. Installer XcodeGen : `brew install xcodegen`.
3. Ajouter votre configuration Firebase dans `TorpilleIOS/Resources/GoogleService-Info.plist`.
4. Exécuter `xcodegen generate`.
5. Ouvrir `TorpilleIOS.xcodeproj` et configurer le bundle identifier et l’équipe de signature.
6. Résoudre les dépendances et lancer sur simulateur ou iPhone.

Conserver les configurations locales et fichiers de signature hors du dépôt.

## Configuration et validation

Configurer Firebase Authentication, Firestore, Storage et les Cloud Functions, notamment `videoSignedUrl` et `sendTorpilleNotification`. Vérifier les autorisations de localisation et de photothèque. Les notifications, invitations, médias et échanges avec Android nécessitent des tests sur appareils configurés.

## Backend et invitations

Les invitations utilisent `https://torpille-38783.web.app/join?cid=<communityId>`. Le backend est partagé avec Android : coordonner tout déploiement des règles et fonctions.

Voir [FIREBASE_DEPLOYMENT.md](FIREBASE_DEPLOYMENT.md) et [APP_REVIEW_SUBMISSION.md](APP_REVIEW_SUBMISSION.md).
