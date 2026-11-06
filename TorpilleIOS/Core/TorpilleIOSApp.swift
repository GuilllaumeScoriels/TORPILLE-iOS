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
import FirebaseMessaging
import FirebaseAuth

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

final class TorpilleAppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, ObservableObject {
    @Published private(set) var environment: AppEnvironment?
    @Published private(set) var launchCompleted = false
    private func publishFCMToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        PushRegistrationDiagnostics.log("FCM registration token received")
        NotificationCenter.default.post(
            name: .torpilleDidReceiveFCMToken,
            object: nil,
            userInfo: ["token": token]
        )
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Return to UIKit before initializing Firebase Auth or notification services.
        // Their startup can consult UIApplication and must not hold up app launch.
        return true
    }

    @MainActor
    func prepareEnvironmentIfNeeded() {
        guard !launchCompleted else { return }
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            AppCheck.setAppCheckProviderFactory(TorpilleAppCheckProviderFactory())
            FirebaseApp.configure()
        }
        if FirebaseApp.app() != nil {
            let env = AppEnvironment()
            environment = env
            Messaging.messaging().delegate = self
        }
        launchCompleted = true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        PushRegistrationDiagnostics.log("APNs device token received")
        #if DEBUG
        // Xcode Debug builds use the development provisioning profile. Explicitly
        // bind both Firebase services to Sandbox so SDK environment inference
        // cannot route this development-signed installation to production APNs.
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
        PushRegistrationDiagnostics.log("APNs environment=sandbox (Xcode Debug)")
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        Messaging.messaging().apnsToken = deviceToken
        #endif
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                Task { @MainActor in
                    self?.environment?.notificationCenterService.reportPushRegistrationFailure(error)
                }
                return
            }
            self?.publishFCMToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        environment?.notificationCenterService.reportPushRegistrationFailure(error)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if FirebaseApp.app() != nil, Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.noData)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard FirebaseApp.app() != nil else { return false }
        return Auth.auth().canHandle(url)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        publishFCMToken(fcmToken)
    }
}

@main
struct TorpilleIOSApp: App {
    @UIApplicationDelegateAdaptor(TorpilleAppDelegate.self) private var appDelegate

    init() {
        // Keep only a small in-memory cache. Reusable media bytes live mostly
        // on disk and are evicted automatically instead of accumulating while
        // users browse high-volume, mostly one-shot content.
        URLCache.shared = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "torpille-media-cache"
        )

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .white
        tabBarAppearance.shadowColor = UIColor.black.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }

    }

    var body: some Scene {
        WindowGroup {
            AppStartupView(appDelegate: appDelegate)
                .preferredColorScheme(ColorScheme.light)
        }
    }
}

/// Observe the published launch state in a view. UIApplicationDelegateAdaptor
/// installs the delegate, but is not the observation owner for this view's state.
private struct AppStartupView: View {
    @ObservedObject var appDelegate: TorpilleAppDelegate

    var body: some View {
        Group {
            if let env = appDelegate.environment {
                AppRootView(viewModel: AppRootViewModel(env: env))
            } else if appDelegate.launchCompleted {
                FirebaseSetupRequiredView()
            } else {
                ZStack {
                    Color.white.ignoresSafeArea()
                    ProgressView("Torpille")
                        .tint(.blue)
                        .foregroundStyle(.black)
                }
            }
        }
        .task { @MainActor in
            appDelegate.prepareEnvironmentIfNeeded()
        }
    }
}

private struct FirebaseSetupRequiredView: View {
    @StateObject private var languageService = AppLanguageService()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 42))
                Text(languageService.phrase("Application indisponible"))
                    .font(.title2)
                    .bold()
                Text(languageService.phrase("Cette version de l’application ne peut pas démarrer."))
                Text(languageService.phrase("Installe la dernière mise à jour de Torpille. Si le problème persiste, contacte l’assistance."))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Torpille")
        }
    }
}
