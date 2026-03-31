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
    @StateObject var viewModel: AppRootViewModel

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
                    }, onOpenGlobalLeaderboard: {
                        viewModel.route = .globalLeaderboard
                    }, onSignOut: {
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
                }
            }
        }
        .onOpenURL { url in
            viewModel.handleIncomingURL(url)
        }
    }
}

struct MainTabView: View {
    let env: AppEnvironment
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenGlobalLeaderboard: () -> Void
    let onSignOut: () -> Void

    @StateObject private var launchLocationSyncViewModel: LaunchLocationSyncViewModel

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenGlobalLeaderboard: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.env = env
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenGlobalLeaderboard = onOpenGlobalLeaderboard
        self.onSignOut = onSignOut
        _launchLocationSyncViewModel = StateObject(
            wrappedValue: LaunchLocationSyncViewModel(
                repo: env.communityRepository,
                locationService: env.locationService
            )
        )
    }

    var body: some View {
        TabView {
            HomeScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity, onOpenGlobalLeaderboard: onOpenGlobalLeaderboard, onSignOut: onSignOut)
                .tabItem { Label("Accueil", systemImage: "house.fill") }

            CommunitiesTabScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity)
                .tabItem { Label("Communautés", systemImage: "person.3.fill") }

            UserProfileScreen(env: env, onEditProfile: {}, onOpenGlobalLeaderboard: onOpenGlobalLeaderboard, onSignOut: onSignOut)
                .tabItem { Label("Profil", systemImage: "person.fill") }

            GlobalLeaderboardScreen(env: env)
                .tabItem { Label("Classement", systemImage: "trophy.fill") }

            TorpilleursMapScreen(env: env)
                .tabItem { Label("Carte", systemImage: "map.fill") }
        }
        .task {
            await launchLocationSyncViewModel.syncOnAppOpenIfNeeded()
        }
    }
}
