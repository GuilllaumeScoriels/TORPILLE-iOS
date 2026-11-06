/**
 Fichier : AppRootView.swift
 Rôle :
 - Gère la navigation principale de l'application iOS.

 Ce que fait ce fichier :
 - Reprend le routage de la version Android avec les mêmes écrans métier.
 - Utilise une `NavigationStack` simple pour rester facile à ouvrir et adapter.
 */

import SwiftUI
import FirebaseAuth

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: AppRootViewModel
    @StateObject private var launchLocationSyncViewModel: LaunchLocationSyncViewModel
    @ObservedObject private var languageService: AppLanguageService
    @ObservedObject private var notificationService: NotificationCenterService
    @State private var mainSelectedTab = 0
    @State private var communityBackDragOffset: CGFloat = 0

    init(viewModel: AppRootViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _launchLocationSyncViewModel = StateObject(
            wrappedValue: LaunchLocationSyncViewModel(
                authRepository: viewModel.env.authRepository,
                repo: viewModel.env.communityRepository
            )
        )
        _languageService = ObservedObject(wrappedValue: viewModel.env.languageService)
        _notificationService = ObservedObject(wrappedValue: viewModel.env.notificationCenterService)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.route {
                case .splash:
                    TorpilleLoadingView(languageService.phrase("Chargement…"))
                        .task { await viewModel.bootstrap() }
                case .auth:
                    AuthScreen(onSignedIn: {
                        try await viewModel.finishAuthentication()
                    }, onSignedUp: {
                        viewModel.route = .profile
                    }, env: viewModel.env)
                case .profile:
                    ProfileSetupScreen(onDone: {
                        Task { await viewModel.resumePendingJoinIfPossible() }
                    }, onBack: {
                        viewModel.env.notificationCenterService.stop()
                        viewModel.route = .auth
                    }, env: viewModel.env)
                case .home:
                    MainTabView(env: viewModel.env, selectedTab: $mainSelectedTab, onCreateCommunity: {
                        viewModel.route = .createCommunity
                    }, onOpenCommunity: {
                        viewModel.route = .community($0)
                    }, onOpenMemories: {
                        viewModel.route = .memories
                    }, onOpenNotificationCenter: {
                        viewModel.openNotificationCenter()
                    }, onSignOut: {
                        mainSelectedTab = 0
                        viewModel.returnToInitialAuthentication()
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
                    interactiveCommunityRoute(communityId: communityId)
                case .communityInfo(let communityId):
                    CommunityInfoScreen(env: viewModel.env, communityId: communityId, onBack: { viewModel.route = .community(communityId) }, onLeft: { viewModel.route = .home })
                case .globalLeaderboard:
                    GlobalLeaderboardScreen(env: viewModel.env, onBack: { viewModel.route = .home })
                case .notificationCenter:
                    NotificationCenterScreen(env: viewModel.env, onBack: { viewModel.route = .home })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if shouldShowHomeTopActions {
                        HStack(spacing: 14) {
                            Button {
                                viewModel.route = .memories
                            } label: {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title3.weight(.semibold))
                            }
                            .accessibilityLabel(languageService.text(.reels))

                            Button {
                                viewModel.openNotificationCenter()
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: notificationService.unreadCount > 0 ? "bell.badge.fill" : "bell.fill")
                                        .font(.title3.weight(.semibold))
                                    if notificationService.unreadCount > 0 {
                                        Text("\(min(notificationService.unreadCount, 99))")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.red)
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                            .offset(x: 12, y: -10)
                                    }
                                }
                            }
                            .accessibilityLabel(languageService.phrase("Activité"))
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .onOpenURL { url in
            if !Auth.auth().canHandle(url) { viewModel.handleIncomingURL(url) }
        }
        .task {
            await launchLocationSyncViewModel.syncOnAppOpenIfNeeded()
        }
        .task(id: scenePhase) {
            // Present the system permission dialog only once the scene is visible.
            guard scenePhase == .active else { return }
            await notificationService.requestAuthorizationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await launchLocationSyncViewModel.syncOnAppActive()
            }
        }
        .onReceive(viewModel.env.notificationCenterService.$navigationTarget) { target in
            guard let target else { return }
            guard viewModel.route != .profile, viewModel.route != .auth, viewModel.route != .splash else { return }
            if target == "communityDiscussion",
               let communityId = viewModel.env.notificationCenterService.navigationCommunityId {
                mainSelectedTab = 1
                viewModel.env.notificationCenterService.navigationTarget = nil
                viewModel.env.notificationCenterService.navigationCommunityId = nil
                viewModel.openCommunityFromNotification(communityId)
            } else if target == "notificationCenter" {
                viewModel.env.notificationCenterService.navigationTarget = nil
                viewModel.openNotificationCenter()
            }
        }
        .environment(\.locale, languageService.locale)
        .environmentObject(languageService)
    }

    private var shouldShowHomeTopActions: Bool {
        viewModel.route == .home && mainSelectedTab == 0
    }

    private var communitiesBackground: some View {
        MainTabView(
            env: viewModel.env,
            selectedTab: .constant(1),
            onCreateCommunity: {},
            onOpenCommunity: { _ in },
            onOpenMemories: {},
            onOpenNotificationCenter: {},
            onSignOut: {}
        )
        .allowsHitTesting(false)
    }

    private func interactiveCommunityRoute(communityId: String) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                communitiesBackground
                    .scaleEffect(0.985 + min(communityBackDragOffset / max(proxy.size.width, 1), 1) * 0.015)
                    .opacity(0.92 + min(communityBackDragOffset / max(proxy.size.width, 1), 1) * 0.08)

                CommunityScreen(
                    env: viewModel.env,
                    communityId: communityId,
                    onBack: {
                        finishCommunityBack()
                    },
                    onOpenInfo: {
                        viewModel.route = .communityInfo(communityId)
                    }
                )
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: communityBackDragOffset > 0 ? 20 : 0, style: .continuous))
                .shadow(color: Color.black.opacity(communityBackDragOffset > 0 ? 0.18 : 0), radius: 18, x: -4, y: 0)
                .offset(x: communityBackDragOffset)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.88), value: communityBackDragOffset)
                .simultaneousGesture(communityBackGesture(width: proxy.size.width))
            }
            .ignoresSafeArea(.container, edges: communityBackDragOffset > 0 ? [] : .bottom)
            .onAppear {
                communityBackDragOffset = 0
            }
        }
    }

    private func communityBackGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let startedNearLeadingEdge = value.startLocation.x <= 28
                let horizontalMovement = value.translation.width
                let verticalMovement = abs(value.translation.height)
                guard startedNearLeadingEdge, horizontalMovement > 0, horizontalMovement > verticalMovement else { return }
                communityBackDragOffset = min(horizontalMovement, width)
            }
            .onEnded { value in
                let startedNearLeadingEdge = value.startLocation.x <= 28
                let horizontalMovement = value.translation.width
                let predictedMovement = value.predictedEndTranslation.width
                let verticalMovement = abs(value.translation.height)
                guard startedNearLeadingEdge, horizontalMovement > 0, horizontalMovement > verticalMovement else {
                    communityBackDragOffset = 0
                    return
                }

                let shouldFinish = horizontalMovement > width * 0.34 || predictedMovement > width * 0.52
                if shouldFinish {
                    communityBackDragOffset = width
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        finishCommunityBack()
                    }
                } else {
                    communityBackDragOffset = 0
                }
            }
    }

    private func finishCommunityBack() {
        communityBackDragOffset = 0
        mainSelectedTab = 1
        viewModel.route = .home
    }
}

struct MainTabView: View {
    let env: AppEnvironment
    @Binding private var selectedTab: Int
    @State private var visitedTabs: Set<Int> = []
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenMemories: () -> Void
    let onOpenNotificationCenter: () -> Void
    let onSignOut: () -> Void
    @ObservedObject private var languageService: AppLanguageService

    init(env: AppEnvironment, selectedTab: Binding<Int>, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenMemories: @escaping () -> Void, onOpenNotificationCenter: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.env = env
        _selectedTab = selectedTab
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenMemories = onOpenMemories
        self.onOpenNotificationCenter = onOpenNotificationCenter
        self.onSignOut = onSignOut
        _languageService = ObservedObject(wrappedValue: env.languageService)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ZStack {
                if selectedTab == 0 || visitedTabs.contains(0) {
                    HomeScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity, onOpenMemories: onOpenMemories, onOpenProfile: {
                        selectedTab = 2
                    }, onOpenNotificationCenter: onOpenNotificationCenter, onOpenGlobalLeaderboard: {
                        selectedTab = 3
                    }, onSignOut: onSignOut)
                }
            }
                .tabItem { Label(languageService.text(.home), systemImage: "house.fill") }
                .tag(0)

            ZStack {
                if selectedTab == 1 || visitedTabs.contains(1) {
                    CommunitiesTabScreen(env: env, onCreateCommunity: onCreateCommunity, onOpenCommunity: onOpenCommunity)
                }
            }
                .tabItem { Label(languageService.text(.communities), systemImage: "person.3.fill") }
                .tag(1)

            ZStack {
                if selectedTab == 2 || visitedTabs.contains(2) {
                    UserProfileScreen(env: env, onEditProfile: {}, onOpenGlobalLeaderboard: {
                        selectedTab = 3
                    }, onSignOut: onSignOut)
                }
            }
                .tabItem { Label(languageService.text(.profile), systemImage: "person.fill") }
                .tag(2)

            ZStack {
                if selectedTab == 3 || visitedTabs.contains(3) {
                    GlobalLeaderboardScreen(env: env)
                }
            }
                .tabItem { Label(languageService.text(.leaderboard), systemImage: "trophy.fill") }
                .tag(3)

            ZStack {
                if selectedTab == 4 || visitedTabs.contains(4) {
                    TorpilleursMapScreen(env: env)
                }
            }
                .tabItem { Label(languageService.text(.map), systemImage: "map.fill") }
                .tag(4)
        }
        .onAppear { visitedTabs.insert(selectedTab) }
        .onChange(of: selectedTab) { _, tab in visitedTabs.insert(tab) }
        .toolbarBackground(Color.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .environment(\.locale, languageService.locale)
        .environmentObject(languageService)
    }
}
