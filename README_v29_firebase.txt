Modifications Firebase à appliquer pour l'écran communauté v29

Firestore
- Dans chaque document messages, autoriser aussi les champs suivants :
  - type = "image"
  - imageUrl
  - imageBucket
  - imagePath
- Dans chaque document members, autoriser :
  - lastSeenTorpilleAt

Exemple message image :
{
  "type": "image",
  "senderUid": "uid",
  "senderPseudo": "pseudo",
  "imageUrl": "https://...",
  "imageBucket": "bucket",
  "imagePath": "communities/<communityId>/images/<filename>",
  "createdAt": <timestamp>
}

Storage
- Ajouter les chemins suivants :
  - communities/{communityId}/images/{fileName}
  - communities/{communityId}/videos/{fileName}
  - communities/{communityId}/audios/{fileName}

Exemple minimal de règles Storage :
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /communities/{communityId}/{mediaType}/{fileName} {
      allow read, write: if request.auth != null;
    }

    match /users/{uid}/profile/{fileName} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
  }
}

Exemple minimal de règles Firestore :
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() {
      return request.auth != null;
    }

    match /communities/{communityId} {
      allow read: if signedIn();

      match /messages/{messageId} {
        allow read, create: if signedIn();
      }

      match /torpilles/{torpilleId} {
        allow read, create, update: if signedIn();
      }

      match /members/{uid} {
        allow read: if signedIn();
        allow create, update: if signedIn() && request.auth.uid == uid;
      }
    }
  }
}
