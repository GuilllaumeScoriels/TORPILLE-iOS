Correction notifications Torpille iOS

Ajouts principaux
- Centre de notifications avec historique local.
- Bouton cloche en haut à droite de l'écran d'accueil.
- Préférences par communauté :
  - Tout
  - Seulement moi
- Notifications locales déclenchées à partir des nouveaux événements Firestore observés par l'app.
- Appui sur une notification : ouverture du centre de notifications dans l'application.
- Badge compteur non lu sur l'icône de l'app et sur la cloche d'accueil.

Comportement
- Mode "Tout" : notification pour nouveaux messages/vidéos/images/vocaux d'une communauté.
- Mode "Seulement moi" : notification quand l'utilisateur est identifié.
- Les préférences sont stockées dans Firestore sous :
  users/{uid}/notificationPreferences/{communityId}

Fichiers modifiés
- TorpilleIOS/Core/AppEnvironment.swift
- TorpilleIOS/Core/TorpilleIOSApp.swift
- TorpilleIOS/Models/Models.swift
- TorpilleIOS/Repositories/Services.swift
- TorpilleIOS/ViewModels/ViewModels.swift
- TorpilleIOS/Views/Screens/AppRootView.swift
- TorpilleIOS/Views/Screens/HomeAndProfileScreens.swift

Point important
- Cette correction termine la logique applicative iOS côté app et le centre de notifications.
- Pour une réception push distante Apple/FCM même quand l'app est totalement fermée, il faut en plus que les capacités push/APNs/FCM soient actives dans le projet Apple Developer/Firebase côté build de production.
