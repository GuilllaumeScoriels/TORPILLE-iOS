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
