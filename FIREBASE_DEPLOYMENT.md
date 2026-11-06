# Publication Firebase du projet Torpille

Projet Firebase attendu : `torpille-38783` (voir `.firebaserc`). Exécuter les commandes depuis la racine du dépôt.

## Préparation sur un nouveau poste ou après expiration de session

```bash
firebase login
firebase use torpille-38783
firebase projects:list
```

Vérifier que `torpille-38783` est bien le projet actif avant chaque publication.

## Firestore

À publier après toute modification de `firestore.rules` :

```bash
firebase deploy --only firestore:rules --project torpille-38783
```

La localisation requiert dans `/users/{uid}` et `/communities/{communityId}/members/{uid}` les champs `lastLatitude`, `lastLongitude` et `lastLocationUpdatedAt`. Aucun index Firestore supplémentaire n'est requis pour ce flux.

## Storage

À publier après toute modification de `storage.rules` :

```bash
firebase deploy --only storage --project torpille-38783
```

## Cloud Functions

À publier après toute modification de `functions/index.js`, `functions/package.json` ou de ses dépendances :

```bash
cd functions
npm install
cd ..
firebase deploy --only functions --project torpille-38783
```

Pour une seule fonction :

```bash
firebase deploy --only functions:NOM_DE_LA_FONCTION --project torpille-38783
```

### Modération et délai de 24 heures

Configurer `MODERATOR_UIDS` avec les UID Firebase Auth des comptes autorisés à statuer sur les signalements, ainsi que `REPORT_OWNER_EMAIL` pour les alertes. Ne jamais placer le mot de passe SMTP dans le dépôt : il doit rester dans le secret `SMTP_PASS`.

Les fonctions de modération importantes sont :

- `onReportCreated` : quarantaine uniquement si le contenu a été signalé **et** contient un terme de la liste bannie, puis notification et échéance enregistrée à 24 heures ;
- `resolveModerationReport` : décision authentifiée `uphold` ou `dismiss` par un UID présent dans `MODERATOR_UIDS` ;
- `notifyOverdueModerationReports` : contrôle toutes les 15 minutes et relance les modérateurs lorsque le délai de 24 heures est dépassé, sans prendre de décision automatique.

Seule une décision humaine `uphold`, authentifiée par l'UID d'un modérateur autorisé, supprime le document et son média, bannit l'auteur de la communauté, désactive son compte Firebase Auth et révoque ses sessions. Une correspondance lexicale ou l'arrivée à échéance ne peut jamais confirmer automatiquement une infraction.

## Hosting

À publier après une modification de `Hosting/public` ou de la configuration Hosting :

```bash
firebase deploy --only hosting --project torpille-38783
```

## Publication groupée

Ne publier que les composants effectivement modifiés :

```bash
firebase deploy --only firestore:rules,storage,functions,hosting --project torpille-38783
```

## Ce qui ne se publie pas avec Firebase CLI

- `GoogleService-Info.plist` est intégré à une nouvelle version iOS, publiée via Xcode/TestFlight/App Store.
- Les permissions iOS, notamment `NSLocationWhenInUseUsageDescription`, nécessitent une nouvelle version de l'app.
- App Check, APNs et l'activation d'API se configurent dans les consoles Firebase/Apple/Google Cloud ; ils ne sont pas déployés par les commandes ci-dessus.

## Contrôle après publication

La commande doit se terminer par `Deploy complete!`. Tester ensuite avec un compte réel et contrôler dans Firestore que les trois champs de localisation sont présents sur le profil et le document membre. En cas d'échec, conserver la sortie complète de la commande et les logs Xcode/Firebase associés.

## Notifications iOS en veille : contrôle de la clé API

Si le journal iPhone contient `API_KEY_SERVICE_BLOCKED` pour
`firebaseinstallations.googleapis.com`, aucun jeton FCM ne peut être créé et le
serveur signale `push skipped: no FCM tokens`. Autoriser **Firebase Installations
API** dans les restrictions de la clé utilisée par `GoogleService-Info.plist`,
en conservant les autres restrictions. L’activation de l’API sur le projet ne
suffit pas si la clé elle-même bloque son utilisation.

Correction appliquée le 25 octobre 2026 au projet `torpille-38783` : ajout de
`firebaseinstallations.googleapis.com` aux trois services déjà autorisés
(`identitytoolkit.googleapis.com`, `securetoken.googleapis.com`,
`firebaseappcheck.googleapis.com`). Redémarrer l’app après propagation pour
réinitialiser le délai de nouvelle tentative du SDK après un refus 403.

Dans une version Debug, les traces `[Push]` permettent de vérifier séparément :
permissions de son et d’écran verrouillé, réception du jeton APNs, réception du
jeton FCM et confirmation de sa sauvegarde. Les jetons ne sont jamais affichés
par ces traces. La présence d’un jeton sauvegardé ne confirme pas à elle seule
la livraison APNs : vérifier ensuite un envoi sur appareil verrouillé ainsi que
la clé APNs configurée dans Firebase Cloud Messaging.

Les alertes serveur utilisent déjà `apns-push-type: alert`, la priorité `10` et
`aps.sound: default`. iOS gère leur affichage même lorsque l’app est suspendue.
Les options **Autoriser les notifications**, **Écran verrouillé** et **Sons**
doivent être activées pour Torpille. Les notifications ordinaires respectent le
mode silencieux et les modes de concentration de l’utilisateur.

### Refus de sauvegarde avec un profil complet

Les règles Firestore ont un budget de 1 000 expressions par requête. Vérifier
la mise à jour ciblée des jetons avant la validation complète du profil évite
que cette dernière épuise ce budget. Le propriétaire authentifié est toujours
vérifié et `affectedKeys()` limite l’écriture à `uid`, `fcmToken`, `fcmTokens`
et `updatedAt`. Le client conserve au maximum dix jetons dans une transaction.

Régression reproduite et corrigée sur l’émulateur avec des données fictives :
`tools/push-notification-rules-test.cjs`. Le test accepte `RULE_TEST_PACKAGE`
(chemin du package contenant `@firebase/rules-unit-testing` et `firebase`) et
`PUSH_RULES_PATH` (règles à tester), et utilise Firestore local sur le port 8192.

### Validation sur iPhone réel le 26 octobre 2026

Le build Debug installé par Xcode possède `aps-environment = development`.
Firebase Cloud Messaging doit disposer d’une clé APNs **de développement** ;
une clé de production seule provoquait ici `Invalid APNs credential`.
Une clé Sandbox limitée à `com.torpille.ios` a été créée puis importée dans
Firebase avec autorisation explicite. La clé de production a été conservée.

Les builds Debug lient maintenant explicitement Firebase Auth et Messaging à
APNs Sandbox. Après cette correction, les bannières FCM ont été constatées sur
l’iPhone 13 connecté, au premier plan puis sur écran verrouillé ; le son du
dernier test en veille a été confirmé par l’utilisateur. Le format serveur
standard fonctionne sans modification de la charge APNs.

Rapport : `verification/notifications-real-device-2026-10-26/README.md`.
