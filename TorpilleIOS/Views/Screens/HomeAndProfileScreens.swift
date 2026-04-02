import SwiftUI

struct HomeScreen: View {
    @StateObject private var vm: HomeViewModel
    @ObservedObject private var notificationService: NotificationCenterService
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenProfile: () -> Void
    let onOpenNotificationCenter: () -> Void
    let onOpenGlobalLeaderboard: () -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenProfile: @escaping () -> Void, onOpenNotificationCenter: @escaping () -> Void, onOpenGlobalLeaderboard: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenProfile = onOpenProfile
        self.onOpenNotificationCenter = onOpenNotificationCenter
        self.onOpenGlobalLeaderboard = onOpenGlobalLeaderboard
        self.onSignOut = onSignOut
        _notificationService = ObservedObject(wrappedValue: env.notificationCenterService)
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "Bienvenue \(vm.me?.pseudo ?? "capitaine")",
                    subtitle: "Retrouve tes communautés, lance une torpille et grimpe dans le classement avec une interface plus chaleureuse.",
                    primarySymbol: "house.fill",
                    secondarySymbol: "sparkles",
                    cornerSymbol: "bolt.fill",
                    accent: .ocean
                )

                profileSummaryCard

                SectionTitleView(title: "Actions rapides", subtitle: "Tout ce dont tu as besoin dès l'ouverture de l'app.")

                Button(action: onCreateCommunity) {
                    IllustratedActionButton(
                        title: "Créer une communauté",
                        subtitle: "Lance un nouvel espace avec ton propre rythme de réponse.",
                        systemImage: "person.3.fill",
                        illustrationSymbol: "plus.bubble.fill",
                        accent: .sunset
                    )
                }
                .buttonStyle(.plain)

                Button(action: onOpenGlobalLeaderboard) {
                    IllustratedActionButton(
                        title: "Classement global",
                        subtitle: "Découvre les joueurs les plus rapides et les plus actifs.",
                        systemImage: "trophy.fill",
                        illustrationSymbol: "rosette",
                        accent: .gold
                    )
                }
                .buttonStyle(.plain)


                SectionTitleView(title: "Mes communautés", subtitle: vm.communities.isEmpty ? "Aucune communauté pour le moment." : "Choisis une communauté pour entrer directement dans l'action.")

                if vm.communities.isEmpty {
                    ContentUnavailableView("Aucune communauté", systemImage: "person.3.sequence.fill", description: Text("Crée ta première communauté pour commencer à jouer."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                } else {
                    ForEach(vm.communities, id: \.stableId) { community in
                        Button {
                            onOpenCommunity(community.stableId)
                        } label: {
                            IllustratedActionButton(
                                title: community.name,
                                subtitle: "\(community.isPublic ? "Publique" : "Privée") · Réponse en \(community.responseTimeSeconds)s",
                                systemImage: community.isPublic ? "person.3.sequence.fill" : "lock.shield.fill",
                                illustrationSymbol: "bubble.left.and.bubble.right.fill",
                                accent: community.isPublic ? .meadow : .violet,
                                trailingText: community.isPublic ? "Public" : "Privé"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Accueil")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenNotificationCenter) {
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
                .accessibilityLabel("Centre de notifications")
            }
        }
        .reserveMainTabBarSpace()
        .onAppear {
            vm.start()
            notificationService.start()
        }
    }

    private var profileSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button(action: onOpenProfile) {
                    ProfileAvatarImageView(
                        imageData: nil,
                        photoURL: vm.me?.photoUrl,
                        fallbackSymbol: "person.crop.circle.badge.checkmark",
                        size: 60
                    )
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ouvrir le profil")

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.me?.pseudo ?? "Utilisateur")
                        .font(.headline)
                    Text(vm.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("XP total : \(vm.me?.xpTotal ?? 0)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ActionAccent.sunset.tint)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct CommunitiesTabScreen: View {
    @StateObject private var vm: HomeViewModel
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void) {
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "Tes communautés",
                    subtitle: "Retrouve rapidement tes groupes et ouvre celui que tu veux en un geste.",
                    primarySymbol: "person.3.fill",
                    secondarySymbol: "bubble.left.and.bubble.right",
                    cornerSymbol: "flag.fill",
                    accent: .violet
                )

                Button(action: onCreateCommunity) {
                    IllustratedActionButton(
                        title: "Créer une nouvelle communauté",
                        subtitle: "Ajoute un nouveau terrain de jeu pour tes torpilles.",
                        systemImage: "plus.circle.fill",
                        illustrationSymbol: "person.3.sequence.fill",
                        accent: .sunset
                    )
                }
                .buttonStyle(.plain)

                ForEach(vm.communities, id: \.stableId) { community in
                    Button {
                        onOpenCommunity(community.stableId)
                    } label: {
                        IllustratedActionButton(
                            title: community.name,
                            subtitle: community.isPublic ? "Communauté publique" : "Communauté privée",
                            systemImage: community.isPublic ? "person.2.wave.2.fill" : "lock.fill",
                            illustrationSymbol: "flag.2.crossed.fill",
                            accent: community.isPublic ? .meadow : .berry
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Communautés")
        .reserveMainTabBarSpace()
        .onAppear { vm.start() }
    }
}

struct UserProfileScreen: View {
    @StateObject private var vm: HomeViewModel
    @State private var pseudoDraft = ""
    @State private var selectedPhotoData: Data?
    @State private var isSavingProfile = false

    let onEditProfile: () -> Void
    let onOpenGlobalLeaderboard: () -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onEditProfile: @escaping () -> Void, onOpenGlobalLeaderboard: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onEditProfile = onEditProfile
        self.onOpenGlobalLeaderboard = onOpenGlobalLeaderboard
        self.onSignOut = onSignOut
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "Ton profil",
                    subtitle: "Personnalise ton identité et gère rapidement tes actions de compte.",
                    primarySymbol: "person.crop.circle.fill",
                    secondarySymbol: "wand.and.stars",
                    cornerSymbol: "pencil.line",
                    accent: .berry
                )

                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        ProfileAvatarView(photoURL: vm.me?.photoUrl, imageData: selectedPhotoData)
                        Spacer()
                    }

                    ProfilePhotoPicker(selectedImageData: $selectedPhotoData)

                    TextField("Pseudo", text: $pseudoDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    infoRow(title: "Email", value: vm.email, symbol: "envelope.fill")
                    infoRow(title: "Mot de passe", value: "••••••••", symbol: "lock.fill")

                    Text("Le mot de passe actuel ne peut pas être relu depuis Firebase Auth. Tu peux toutefois le réinitialiser par email.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    Task {
                        isSavingProfile = true
                        let didSave = await vm.saveProfile(pseudo: pseudoDraft, imageData: selectedPhotoData, profileIcon: nil)
                        isSavingProfile = false
                        if didSave {
                            selectedPhotoData = nil
                            onEditProfile()
                        }
                    }
                } label: {
                    IllustratedActionButton(
                        title: isSavingProfile ? "Enregistrement…" : "Enregistrer les modifications",
                        subtitle: "Mets à jour ton pseudo et ta photo de profil.",
                        systemImage: "square.and.arrow.down.fill",
                        illustrationSymbol: "checkmark.seal.fill",
                        accent: .meadow
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavingProfile)

                Button {
                    vm.resetPassword()
                } label: {
                    IllustratedActionButton(
                        title: "Réinitialiser le mot de passe",
                        subtitle: "Reçois un email pour définir un nouveau mot de passe.",
                        systemImage: "key.fill",
                        illustrationSymbol: "envelope.badge.fill",
                        accent: .gold
                    )
                }
                .buttonStyle(.plain)

                Button(action: onOpenGlobalLeaderboard) {
                    IllustratedActionButton(
                        title: "Voir le classement global",
                        subtitle: "Compare ton score avec celui de toute la communauté Torpille.",
                        systemImage: "trophy.fill",
                        illustrationSymbol: "chart.bar.fill",
                        accent: .ocean
                    )
                }
                .buttonStyle(.plain)

                Button {
                    vm.signOut(onDone: onSignOut)
                } label: {
                    IllustratedActionButton(
                        title: "Déconnexion",
                        subtitle: "Quitte la session actuelle en toute sécurité.",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        illustrationSymbol: "door.right.hand.open",
                        accent: .coral
                    )
                }
                .buttonStyle(.plain)

                /*if let info = vm.infoMessage {
                    Text(info)
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let error = vm.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }*/
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Profil")
        .reserveMainTabBarSpace()
        .onAppear {
            vm.start()
            pseudoDraft = vm.me?.pseudo ?? pseudoDraft
            selectedPhotoData = nil
        }
        .onChange(of: vm.me?.pseudo ?? "") { _, newValue in
            if !newValue.isEmpty, pseudoDraft.isEmpty {
                pseudoDraft = newValue
            }
        }
    }

    private func infoRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(ActionAccent.violet.tint)
                .frame(width: 36, height: 36)
                .background(ActionAccent.violet.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ProfileAvatarView: View {
    let photoURL: String?
    let imageData: Data?

    var body: some View {
        ProfileAvatarImageView(
            imageData: imageData,
            photoURL: photoURL,
            fallbackSymbol: "person.crop.circle.fill",
            size: 104
        )
    }
}


struct GlobalLeaderboardScreen: View {
    @StateObject private var vm: GlobalLeaderboardViewModel

    init(env: AppEnvironment) {
        _vm = StateObject(
            wrappedValue: GlobalLeaderboardViewModel(
                repo: env.userRepository,
                authRepository: env.authRepository,
                communityRepository: env.communityRepository
            )
        )
    }

    var body: some View {
        List {
            Section {
                WelcomeHeroCard(
                    title: "Classement global",
                    subtitle: "Compare les meilleurs torpilleurs et filtre rapidement le tableau par communauté.",
                    primarySymbol: "trophy.fill",
                    secondarySymbol: "chart.bar.fill",
                    cornerSymbol: "number.circle.fill",
                    accent: .gold
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }

            filtersSection

            if vm.players.isEmpty {
                emptyStateSection
            } else {
                leaderboardSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .navigationTitle("Classement")
        .reserveMainTabBarSpace()
        .onAppear { vm.start() }
    }

    private var filtersSection: some View {
        Section("Filtres") {
            Button {
                vm.clearCommunityFilters()
            } label: {
                CompactActionButton(
                    title: !vm.hasActiveCommunityFilter ? "Classement total activé" : "Revenir au classement total",
                    systemImage: "line.3.horizontal.decrease.circle.fill",
                    accent: .ocean
                )
            }
            .buttonStyle(.plain)

            if vm.availableCommunities.isEmpty {
                Text("Rejoins une ou plusieurs communautés pour filtrer le classement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.availableCommunities, id: \.stableId) { community in
                    Button {
                        vm.toggleCommunity(community.stableId)
                    } label: {
                        CompactActionButton(
                            title: vm.selectedCommunityIds.contains(community.stableId) ? "\(community.name) sélectionnée" : community.name,
                            systemImage: vm.selectedCommunityIds.contains(community.stableId) ? "checkmark.circle.fill" : "circle",
                            accent: vm.selectedCommunityIds.contains(community.stableId) ? .meadow : .slate
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView(
                "Aucun joueur",
                systemImage: "person.3.sequence.fill",
                description: Text("Le classement sera visible dès qu'il y aura des profils à comparer.")
            )
        }
    }

    private var leaderboardSection: some View {
        Section("Joueurs") {
            ForEach(Array(vm.players.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: 12) {
                    Text("#\(index + 1)")
                        .font(.headline)
                        .frame(width: 46, height: 46)
                        .background((index == 0 ? ActionAccent.gold.tint : ActionAccent.ocean.tint).opacity(0.14))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.pseudo)
                            .font(.headline)
                        Text("XP : \(player.xpTotal)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
}


struct NotificationCenterScreen: View {
    @ObservedObject private var notificationService: NotificationCenterService
    let onBack: () -> Void

    init(env: AppEnvironment, onBack: @escaping () -> Void) {
        _notificationService = ObservedObject(wrappedValue: env.notificationCenterService)
        self.onBack = onBack
    }

    var body: some View {
        List {
            Section {
                ForEach(notificationService.communities, id: \.stableId) { community in
                    let preference = notificationService.preference(for: community)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(community.name)
                            .font(.headline)
                        Picker("Notifications", selection: Binding(
                            get: { preference.mode },
                            set: { notificationService.updatePreference(for: community, mode: $0) }
                        )) {
                            ForEach(CommunityNotificationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Choisis si cette communauté doit te notifier pour tous les contenus ou seulement quand tu es identifié·e.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if notificationService.communities.isEmpty {
                    ContentUnavailableView(
                        "Aucune communauté",
                        systemImage: "person.3.sequence.fill",
                        description: Text("Rejoins ou crée une communauté pour configurer tes notifications.")
                    )
                    .frame(maxWidth: .infinity)
                }
            } header: {
                Text("Préférences par communauté")
            }

            Section {
                if notificationService.items.isEmpty {
                    ContentUnavailableView(
                        "Aucune notification",
                        systemImage: "bell.slash",
                        description: Text("Les nouvelles notifications reçues apparaîtront ici.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(notificationService.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.communityName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !item.isRead {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 10, height: 10)
                                }
                            }
                            Text(item.body)
                                .font(.subheadline)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            notificationService.markAsRead(item.id)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                notificationService.deleteNotification(item.id)
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Historique")
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Retour", action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !notificationService.items.isEmpty {
                    Button("Tout lu") {
                        notificationService.markAllAsRead()
                    }
                }
            }
        }
        .onAppear {
            notificationService.start()
            notificationService.markAllAsRead()
        }
    }
}
