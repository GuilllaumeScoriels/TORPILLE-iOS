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
                    AuthScreen(onAuthed: { viewModel.route = .splash }, env: viewModel.env)
                case .profile:
                    ProfileSetupScreen(onDone: { viewModel.route = .splash }, env: viewModel.env)
                case .home:
                    MainTabView(env: viewModel.env, onCreateCommunity: {
                        viewModel.route = .createCommunity
                    }, onOpenCommunity: {
                        viewModel.route = .community($0)
                    }, onSignOut: {
                        viewModel.route = .auth
                    })
                case .createCommunity:
                    CreateCommunityScreen(env: viewModel.env, onCreated: { viewModel.route = .community($0) }, onBack: { viewModel.route = .home })
                case .join(let communityId):
                    JoinCommunityScreen(env: viewModel.env, communityId: communityId, onJoined: { viewModel.route = .communityInfo(communityId) }, onCancel: { viewModel.route = .home })
                case .community(let communityId):
                    CommunityScreen(env: viewModel.env, communityId: communityId, onBack: { viewModel.route = .home }, onOpenInfo: { viewModel.route = .communityInfo(communityId) })
                case .communityInfo(let communityId):
                    CommunityInfoScreen(env: viewModel.env, communityId: communityId, onBack: { viewModel.route = .community(communityId) })
                }
            }
        }
    }
}

struct MainTabView: View {
    let env: AppEnvironment
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onSignOut: () -> Void

    var body: some View {
        TabView {
            HomeScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity, onSignOut: onSignOut)
                .tabItem { Label("Accueil", systemImage: "house.fill") }

            CommunitiesTabScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity)
                .tabItem { Label("Communautés", systemImage: "person.3.fill") }

            UserProfileScreen(env: env, onEditProfile: {}, onSignOut: onSignOut)
                .tabItem { Label("Profil", systemImage: "person.fill") }

            TorpilleursMapScreen(env: env)
                .tabItem { Label("Carte", systemImage: "map.fill") }
        }
    }
}
