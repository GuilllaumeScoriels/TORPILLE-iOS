/**
 Fichier : TorpilleIOSApp.swift
 Rôle :
 - Point d'entrée principal de l'application iOS.

 Ce que fait ce fichier :
 - Configure Firebase au démarrage quand le fichier `GoogleService-Info.plist`
   est présent dans l'application.
 - Monte la racine SwiftUI pilotée par `AppRootViewModel`.
 - Affiche un écran d'installation explicite si la configuration Firebase iOS
   n'a pas encore été copiée dans le projet Xcode.

 À noter :
 - Le fichier `GoogleService-Info.plist` réel doit être ajouté dans `Resources/`.
 */

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAppCheck

final class TorpilleAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        } else {
            return DeviceCheckProvider(app: app)
        }
        #endif
    }
}

@main
struct TorpilleIOSApp: App {
    private let env: AppEnvironment?
    private let firebaseConfigured: Bool

    init() {
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {

            AppCheck.setAppCheckProviderFactory(TorpilleAppCheckProviderFactory())
            FirebaseApp.configure()
        }

        firebaseConfigured = FirebaseApp.app() != nil
        env = firebaseConfigured ? AppEnvironment() : nil
        _ = env?.notificationCenterService

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .white
        tabBarAppearance.shadowColor = UIColor.black.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }

        if !firebaseConfigured {
            print("🔥 Firebase non configuré au démarrage. Vérifie que GoogleService-Info.plist est bien embarqué dans le target iOS.")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let env {
                    AppRootView(viewModel: AppRootViewModel(env: env))
                } else {
                    FirebaseSetupRequiredView()
                }
            }
            .preferredColorScheme(ColorScheme.light)
        }
    }
}

private struct FirebaseSetupRequiredView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 42))
                Text("Configuration Firebase requise")
                    .font(.title2)
                    .bold()
                Text("Ajoute le fichier GoogleService-Info.plist iOS dans le groupe Resources du projet Xcode, puis relance l'application.")
                Text("Le projet source peut s'ouvrir immédiatement dans Xcode, mais les fonctions Firebase ne démarreront qu'après l'ajout de ce fichier.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Torpille")
        }
    }
}
