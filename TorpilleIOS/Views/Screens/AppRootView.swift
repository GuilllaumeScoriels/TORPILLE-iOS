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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AppRootViewModel
    @StateObject private var launchLocationSyncViewModel: LaunchLocationSyncViewModel
    @ObservedObject private var languageService: AppLanguageService

    init(viewModel: AppRootViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _launchLocationSyncViewModel = StateObject(
            wrappedValue: LaunchLocationSyncViewModel(
                authRepository: viewModel.env.authRepository,
                repo: viewModel.env.communityRepository,
                locationService: viewModel.env.locationService
            )
        )
        _languageService = ObservedObject(wrappedValue: viewModel.env.languageService)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.route {
                case .splash:
                    ProgressView(languageService.phrase("Chargement…"))
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
                    }, onOpenMemories: {
                        viewModel.route = .memories
                    }, onOpenNotificationCenter: {
                        viewModel.openNotificationCenter()
                    }, onSignOut: {
                        viewModel.env.notificationCenterService.stop()
                        viewModel.route = .auth
                    })
                case .memories:
                    ReelsScreen(env: viewModel.env, onBack: { viewModel.route = .home })
                case .createCommunity:
                    CreateCommunityScreen(env: viewModel.env, onCreated: { viewModel.route = .communityInfo($0) }, onBack: { viewModel.route = .home })
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
                    GlobalLeaderboardScreen(env: viewModel.env, onBack: { viewModel.route = .home })
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await launchLocationSyncViewModel.syncOnAppActive()
            }
        }
        .onReceive(viewModel.env.notificationCenterService.$navigationTarget) { target in
            guard target == "notificationCenter" else { return }
            viewModel.env.notificationCenterService.navigationTarget = nil
            viewModel.openNotificationCenter()
        }
        .environment(\.locale, languageService.locale)
        .environmentObject(languageService)
    }
}

struct MainTabView: View {
    let env: AppEnvironment
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenMemories: () -> Void
    let onOpenNotificationCenter: () -> Void
    let onSignOut: () -> Void
    @ObservedObject private var languageService: AppLanguageService
    @State private var selectedTab = 0
    @State private var isShowingProfileSheet = false

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenMemories: @escaping () -> Void, onOpenNotificationCenter: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.env = env
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenMemories = onOpenMemories
        self.onOpenNotificationCenter = onOpenNotificationCenter
        self.onSignOut = onSignOut
        _languageService = ObservedObject(wrappedValue: env.languageService)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity, onOpenMemories: onOpenMemories, onOpenProfile: {
                isShowingProfileSheet = true
            }, onOpenNotificationCenter: onOpenNotificationCenter, onOpenGlobalLeaderboard: {
                selectedTab = 3
            }, onSignOut: onSignOut)
                .tabItem { Label(languageService.text(.home), systemImage: "house.fill") }
                .tag(0)

            CommunitiesTabScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity)
                .tabItem { Label(languageService.text(.communities), systemImage: "person.3.fill") }
                .tag(1)

            UserProfileScreen(env: env, onEditProfile: {}, onOpenGlobalLeaderboard: {
                selectedTab = 3
            }, onSignOut: onSignOut)
                .tabItem { Label(languageService.text(.profile), systemImage: "person.fill") }
                .tag(2)

            GlobalLeaderboardScreen(env: env)
                .tabItem { Label(languageService.text(.leaderboard), systemImage: "trophy.fill") }
                .tag(3)

            TorpilleursMapScreen(env: env)
                .tabItem { Label(languageService.text(.map), systemImage: "map.fill") }
                .tag(4)
        }
        .toolbarBackground(Color.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .sheet(isPresented: $isShowingProfileSheet) {
            NavigationStack {
                UserProfileScreen(
                    env: env,
                    onEditProfile: {},
                    onOpenGlobalLeaderboard: {
                        isShowingProfileSheet = false
                        selectedTab = 3
                    },
                    onSignOut: {
                        isShowingProfileSheet = false
                        onSignOut()
                    },
                    onBack: {
                        isShowingProfileSheet = false
                    }
                )
            }
            .presentationDragIndicator(.visible)
        }
        .environment(\.locale, languageService.locale)
        .environmentObject(languageService)
    }
}
