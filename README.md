# Torpille iOS — mise à jour basée sur la version Android améliorée

Cette archive contient une version iOS SwiftUI mise à jour du projet Torpille en se basant sur le ZIP Android fourni.

## Ce qui a été repris depuis l'Android amélioré

- architecture MVVM + repositories
- modèles Firestore alignés avec l'app Android
- écran **Carte des torpilleurs** avec géolocalisation et marqueurs membres
- messages texte + **messages vidéo avec bouton de lecture fonctionnel**
- lecture vidéo native iOS via `AVPlayer`
- overlay de tag (`tagX`, `tagY`, `taggedPseudo`) sur le lecteur
- envoi de torpille vidéo vers Firebase Storage
- réponse vidéo à une torpille en attente
- création / jointure / infos de communauté
- commentaires explicatifs en haut de chaque fichier Swift

## Limite importante

Je ne peux pas compiler ni exécuter Xcode dans cet environnement Linux, donc je ne peux pas certifier une exécution réelle sur iPhone depuis ici. En revanche, la structure source a été mise à jour de manière cohérente avec le ZIP Android, les fichiers ont été réorganisés proprement, et le flux iOS couvre bien les deux ajouts demandés : **carte** et **boutons vidéo**.

## Ouvrir le projet

1. Sur Mac, installer **Xcode**.
2. Installer **XcodeGen** si besoin :
   - `brew install xcodegen`
3. Copier le vrai fichier Firebase iOS `GoogleService-Info.plist` dans `TorpilleIOS/Resources/`.
4. Générer le projet Xcode depuis ce dossier :
   - `xcodegen generate`
5. Ouvrir `TorpilleIOS.xcodeproj`.
6. Vérifier le bundle id et l'équipe de signature.
7. Lancer sur simulateur iPhone ou appareil réel.

## Vérifications à faire dans Xcode

- package Firebase correctement résolu
- permissions localisation et photothèque présentes dans l'Info.plist
- accès réseau autorisé pour Firebase Functions / Storage
- configuration de `videoSignedUrl` et `sendTorpilleNotification`
- existence des règles Firestore / Storage compatibles avec l'app Android

## Remarques techniques

- Le flux vidéo iOS utilise **PhotosPicker** pour choisir une vidéo côté utilisateur.
- La lecture vidéo passe par **AVKit**.
- La carte utilise **MapKit**.
- Le schéma d'URL `torpille://` est prévu dans `project.yml`.

## Fichiers principaux

- `TorpilleIOS/Core/` : bootstrap + erreurs + helpers
- `TorpilleIOS/Models/` : modèles Firestore
- `TorpilleIOS/Repositories/` : Firebase, Storage, Functions, localisation
- `TorpilleIOS/ViewModels/` : logique d'écran
- `TorpilleIOS/Views/` : SwiftUI (écrans + composants)



## Correctifs appliqués

- ajout d'un vrai `Info.plist` dans `TorpilleIOS/Resources/`
- suppression de la dépendance SPM `FirebaseFirestoreSwift` devenue inutile ici
- conservation de `FirebaseFirestore` pour les APIs de décodage Firestore
