Correctifs appliqués

1. Classement global
- Le classement global écoute maintenant toute la collection users au lieu d'une requête limitée et triée uniquement sur xpTotal.
- Résultat : tous les comptes inscrits apparaissent bien dans "Classement total", y compris ceux qui ont 0 XP ou dont le champ xpTotal n'existait pas encore.
- Le tri est fait côté iOS par xpTotal décroissant, puis par pseudo.

2. Création / mise à jour du profil utilisateur
- Lors du upsert du profil, l'app écrit désormais xpTotal = 0 si le champ n'existait pas encore.
- createdAt est aussi posé automatiquement à la création si absent.
- Cela évite que de nouveaux utilisateurs soient invisibles dans certains classements Firestore basés sur xpTotal.

3. Règles Firebase ajoutées au projet
- firestore.rules
- storage.rules

Changements principaux côté règles :
- users autorise maintenant aussi xpTotal et fcmToken.
- Storage restreint l'accès aux médias de communauté aux membres/admins au lieu de n'importe quel utilisateur connecté.

Fichiers modifiés
- TorpilleIOS/Repositories/Repositories.swift
- firestore.rules
- storage.rules

À déployer côté Firebase
- firebase deploy --only firestore:rules
- firebase deploy --only storage
