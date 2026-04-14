Ajout du champ Firestore `xptotal`.

Ce correctif :
- écrit désormais `xptotal` dans `users/{uid}` ;
- continue à lire aussi l'ancien champ `xpTotal` pour compatibilité ;
- utilise `xptotal` pour le classement total ;
- met à jour `firestore.rules` pour autoriser `xptotal` en lecture/écriture côté profil utilisateur.

Déploiement conseillé :
1. Déployer `firestore.rules` et `storage.rules`.
2. Ouvrir l'app avec chaque utilisateur actif pour recalculer son total si besoin.
3. Optionnel : migrer les anciens documents `users/*` de `xpTotal` vers `xptotal` côté script/admin.
