/**
 Fichier : AppRootView.swift
 Rôle :
 - Gère la navigation principale de l'application iOS.

 Ce que fait ce fichier :
 - Reprend le routage de la version Android avec les mêmes écrans métier.
 - Utilise une `NavigationStack` simple pour rester facile à ouvrir et adapter.
 */

import SwiftUI

struct AppRootView: View {
    @StateObject private var viewModel: AppRootViewModel
    @StateObject private var launchLocationSyncViewModel: LaunchLocationSyncViewModel

    init(viewModel: AppRootViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _launchLocationSyncViewModel = StateObject(
            wrappedValue: LaunchLocationSyncViewModel(
                authRepository: viewModel.env.authRepository,
                repo: viewModel.env.communityRepository,
                locationService: viewModel.env.locationService
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.route {
                case .splash:
                    ProgressView("Chargement…")
                        .task { await viewModel.bootstrap() }
                case .auth:
                    AuthScreen(onSignedIn: {
                        Task { await viewModel.resumePendingJoinIfPossible() }
                    }, onSignedUp: {
                        viewModel.route = .profile
                    }, env: viewModel.env)
                case .profile:
                    ProfileSetupScreen(onDone: {
                        Task { await viewModel.resumePendingJoinIfPossible() }
                    }, env: viewModel.env)
                case .home:
                    MainTabView(env: viewModel.env, onCreateCommunity: {
                        viewModel.route = .createCommunity
                    }, onOpenCommunity: {
                        viewModel.route = .community($0)
                    }, onOpenNotificationCenter: {
                        viewModel.openNotificationCenter()
                    }, onSignOut: {
                        viewModel.env.notificationCenterService.stop()
                        viewModel.route = .auth
                    })
                case .createCommunity:
                    CreateCommunityScreen(env: viewModel.env, onCreated: { viewModel.route = .community($0) }, onBack: { viewModel.route = .home })
                case .join(let communityId):
                    JoinCommunityScreen(env: viewModel.env, communityId: communityId, onJoined: {
                        viewModel.clearPendingJoin()
                        viewModel.route = .communityInfo(communityId)
                    }, onCancel: {
                        viewModel.clearPendingJoin()
                        viewModel.route = .home
                    })
                case .community(let communityId):
                    CommunityScreen(env: viewModel.env, communityId: communityId, onBack: { viewModel.route = .home }, onOpenInfo: { viewModel.route = .communityInfo(communityId) })
                case .communityInfo(let communityId):
                    CommunityInfoScreen(env: viewModel.env, communityId: communityId, onBack: { viewModel.route = .community(communityId) })
                case .globalLeaderboard:
                    GlobalLeaderboardScreen(env: viewModel.env)
                case .notificationCenter:
                    NotificationCenterScreen(env: viewModel.env, onBack: { viewModel.route = .home })
                }
            }
        }
        .onOpenURL { url in
            viewModel.handleIncomingURL(url)
        }
        .task {
            await launchLocationSyncViewModel.syncOnAppOpenIfNeeded()
        }
        .onReceive(viewModel.env.notificationCenterService.$navigationTarget) { target in
            guard target == "notificationCenter" else { return }
            viewModel.env.notificationCenterService.navigationTarget = nil
            viewModel.openNotificationCenter()
        }
    }
}

struct MainTabView: View {
    let env: AppEnvironment
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenNotificationCenter: () -> Void
    let onSignOut: () -> Void
    @State private var selectedTab = 0

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenNotificationCenter: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.env = env
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenNotificationCenter = onOpenNotificationCenter
        self.onSignOut = onSignOut
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity, onOpenProfile: {
                selectedTab = 2
            }, onOpenNotificationCenter: onOpenNotificationCenter, onOpenGlobalLeaderboard: {
                selectedTab = 3
            }, onSignOut: onSignOut)
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(0)

            CommunitiesTabScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity)
                .tabItem { Label("Communautés", systemImage: "person.3.fill") }
                .tag(1)

            UserProfileScreen(env: env, onEditProfile: {}, onOpenGlobalLeaderboard: {
                selectedTab = 3
            }, onSignOut: onSignOut)
                .tabItem { Label("Profil", systemImage: "person.fill") }
                .tag(2)

            GlobalLeaderboardScreen(env: env)
                .tabItem { Label("Classement", systemImage: "trophy.fill") }
                .tag(3)

            TorpilleursMapScreen(env: env)
                .tabItem { Label("Carte", systemImage: "map.fill") }
                .tag(4)
        }
        .toolbarBackground(Color.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
    }
}
