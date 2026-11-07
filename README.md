# TORPILLE · iOS

A native social application built with **Swift and SwiftUI**, featuring communities, multimedia messaging, and location sharing.

[Android version](https://github.com/GuilllaumeScoriels/APK_TORPILLE) · [App Store listing](https://apps.apple.com/fr/app/torpille/id6761060711)

## Features

- Create and join communities.
- Send text and video messages, including video torpilles and replies.
- Play videos natively with AVPlayer and display tags.
- View community members on a MapKit map.
- Share invitations and open the app through the `torpille://` URL scheme.

## Architecture

**MVVM architecture with repositories**, backed by Firebase services shared with Android.

| Directory | Purpose |
| --- | --- |
| `TorpilleIOS/Core/` | Initialization and utilities |
| `TorpilleIOS/Models/` | Firestore data models |
| `TorpilleIOS/Repositories/` | Firebase, media, functions, and location services |
| `TorpilleIOS/ViewModels/` | Screen logic |
| `TorpilleIOS/Views/` | SwiftUI screens and components |
| `TorpilleIOSTests/` | Project tests |
| `functions/` | Cloud Functions |
| `Hosting/` | Invitation web page |

**Technologies:** Swift, SwiftUI, Firebase, MapKit, AVKit, PhotosPicker, XcodeGen.

## Getting started

1. Clone this repository on a Mac with Xcode installed.
2. Install XcodeGen: `brew install xcodegen`.
3. Add your Firebase configuration to `TorpilleIOS/Resources/GoogleService-Info.plist`.
4. Run `xcodegen generate`.
5. Open `TorpilleIOS.xcodeproj` and configure the bundle identifier and signing team.
6. Resolve dependencies and run the app on a simulator or iPhone.

Keep local configuration and signing files out of version control.

## Configuration and validation

Configure Firebase Authentication, Firestore, Storage, and Cloud Functions, including `videoSignedUrl` and `sendTorpilleNotification`. Check location and photo library permissions. Notifications, invitations, media, and Android interoperability require testing on configured devices.

## Shared backend and invitations

Invitations use `https://torpille-38783.web.app/join?cid=<communityId>`. The backend is shared with Android: coordinate all rule and function deployments across both platforms.

See [FIREBASE_DEPLOYMENT.md](FIREBASE_DEPLOYMENT.md) and [APP_REVIEW_SUBMISSION.md](APP_REVIEW_SUBMISSION.md).
