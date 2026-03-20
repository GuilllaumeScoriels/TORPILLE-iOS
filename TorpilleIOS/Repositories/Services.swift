/**
 Fichier : Services.swift
 Rôle :
 - Fournit les services techniques utilisés par les repositories iOS.

 Ce que fait ce fichier :
 - `LocationService` demande l'autorisation, lit la position courante et expose
   le dernier emplacement connu pour la carte des torpilleurs.
 - `VideoTransferService` gère l'envoi vers Firebase Storage et la résolution des
   URLs de lecture via Firebase Functions, comme dans la version Android.

 Pourquoi c'est utile :
 - Les détails UIKit / CoreLocation / Firebase restent hors des vues SwiftUI.

 Note de correction :
 - `LocationService` n'est pas annoté `@MainActor` pour éviter les erreurs de
   compilation liées à la conformité `CLLocationManagerDelegate` sous Swift 5.10.
 - Les appels CoreLocation restent néanmoins faits depuis le thread principal de
   l'application iOS, comme prévu par Apple.
 */

import Foundation
@preconcurrency import CoreLocation
import FirebaseAuth
import FirebaseFunctions
import FirebaseStorage

final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionIfNeeded() async throws {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            return
        }
        guard status == .notDetermined else {
            throw TorpilleError.locationUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocation {
        try await requestPermissionIfNeeded()

        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw TorpilleError.locationUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        case .denied, .restricted:
            authorizationContinuation?.resume(throwing: TorpilleError.locationUnavailable)
            authorizationContinuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}

final class VideoTransferService {
    private let storage = Storage.storage()
    private let functions = Functions.functions(region: "europe-west1")

    func uploadCommunityVideo(communityId: String, localFileURL: URL, filename: String) async throws -> UploadedVideo {
        let bucket = storage.reference().bucket
        let path = "communities/\(communityId)/videos/\(filename)"
        let ref = storage.reference(withPath: path)
        _ = try await ref.putFileAsync(from: localFileURL, metadata: nil)
        return UploadedVideo(bucket: bucket, storagePath: path)
    }

    func resolvePlaybackURL(videoPath: String, videoBucket: String?) async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw TorpilleError.notAuthenticated
        }

        _ = try await user.getIDTokenResult(forcingRefresh: true)

        var payload: [String: Any] = [
            "path": videoPath,
            "expiresIn": 3600
        ]
        if let videoBucket, !videoBucket.isEmpty {
            payload["bucket"] = videoBucket
        }

        let result = try await functions.httpsCallable("videoSignedUrl").call(payload)
        guard let data = result.data as? [String: Any],
              let signedURLString = data["signedUrl"] as? String,
              let url = URL(string: signedURLString) else {
            throw TorpilleError.videoNotAvailable
        }

        return url
    }
}
