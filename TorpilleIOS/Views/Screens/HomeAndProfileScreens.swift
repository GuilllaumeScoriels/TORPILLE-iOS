import SwiftUI
import FirebaseFirestore
import FirebaseStorage

struct HomeScreen: View {
    @StateObject private var vm: HomeViewModel
    @ObservedObject private var notificationService: NotificationCenterService
    @ObservedObject private var languageService: AppLanguageService
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenMemories: () -> Void
    let onOpenProfile: () -> Void
    let onOpenNotificationCenter: () -> Void
    let onOpenGlobalLeaderboard: () -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenMemories: @escaping () -> Void, onOpenProfile: @escaping () -> Void, onOpenNotificationCenter: @escaping () -> Void, onOpenGlobalLeaderboard: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenMemories = onOpenMemories
        self.onOpenProfile = onOpenProfile
        self.onOpenNotificationCenter = onOpenNotificationCenter
        self.onOpenGlobalLeaderboard = onOpenGlobalLeaderboard
        self.onSignOut = onSignOut
        _notificationService = ObservedObject(wrappedValue: env.notificationCenterService)
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository, languageService: env.languageService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "\(languageService.phrase("Bienvenue")) \(vm.me?.pseudo ?? languageService.phrase("capitaine"))",
                    subtitle: nil,
                    primarySymbol: "house.fill",
                    secondarySymbol: "sparkles",
                    cornerSymbol: "bolt.fill",
                    accent: .ocean
                )

                if vm.isLoadingProfile {
                    TorpilleLoadingView().frame(maxWidth: .infinity).padding()
                } else {
                    profileSummaryCard
                }

                SectionTitleView(
                    title: vm.pinnedCommunities.isEmpty ? languageService.phrase("Dernière communauté") : languageService.phrase("Communautés épinglées"),
                    subtitle: vm.homeCommunities.isEmpty && !vm.isLoadingCommunities ? languageService.phrase("Aucune communauté pour le moment.") : ""
                )

                if vm.homeCommunities.isEmpty && !vm.isLoadingCommunities {
                    ContentUnavailableView(languageService.phrase("Aucune communauté"), systemImage: "person.3.sequence.fill", description: Text(languageService.phrase("Crée ta première communauté pour commencer à jouer.")))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                } else {
                    ForEach(vm.homeCommunities, id: \.stableId) { community in
                        Button {
                            onOpenCommunity(community.stableId)
                        } label: {
                            IllustratedActionButton(
                                title: community.name,
                                subtitle: "\(languageService.phrase(community.isPublic ? "Publique" : "Privée")) · \(languageService.phrase("Réponse en")) \(formatResponseTime(community.responseTimeSeconds))",
                                systemImage: community.isPublic ? "person.3.sequence.fill" : "lock.shield.fill",
                                illustrationSymbol: "bubble.left.and.bubble.right.fill",
                                accent: community.isPublic ? .meadow : .violet,
                                trailingText: vm.isPinned(community) ? languageService.phrase("Épinglée") : languageService.phrase(community.isPublic ? "Public" : "Privé")
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(languageService.phrase(vm.isPinned(community) ? "Retirer de l’accueil" : "Épingler dans l’accueil")) {
                                vm.togglePinnedCommunity(community)
                            }
                        }
                    }
                }

                if vm.isLoadingCommunities {
                    TorpilleLoadingView().frame(maxWidth: .infinity).padding()
                }
                SectionTitleView(title: languageService.phrase("Actions rapides"), subtitle: "")

                Button(action: onCreateCommunity) {
                    IllustratedActionButton(
                        title: languageService.phrase("Créer une communauté"),
                        subtitle: nil,
                        systemImage: "person.3.fill",
                        illustrationSymbol: "plus.bubble.fill",
                        accent: .sunset
                    )
                }
                .buttonStyle(.plain)

                Button(action: onOpenGlobalLeaderboard) {
                    IllustratedActionButton(
                        title: languageService.phrase("Classement global"),
                        subtitle: nil,
                        systemImage: "trophy.fill",
                        illustrationSymbol: "rosette",
                        accent: .gold
                    )
                }
                .buttonStyle(.plain)

                if let info = vm.infoMessage {
                    Text(info)
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let error = vm.error {
                    Text(languageService.localizedRuntimeMessage(error))
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(languageService.text(.home))
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
                .accessibilityLabel(languageService.phrase("Ouvrir le profil"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.me?.pseudo ?? languageService.phrase("Utilisateur"))
                        .font(.headline)
                    Text(vm.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(languageService.xpTotalLabel(vm.me?.effectiveTotalXP ?? 0))
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
    @ObservedObject private var languageService: AppLanguageService
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void) {
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository, languageService: env.languageService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: languageService.phrase("Tes communautés"),
                    subtitle: nil,
                    primarySymbol: "person.3.fill",
                    secondarySymbol: "bubble.left.and.bubble.right",
                    cornerSymbol: "flag.fill",
                    accent: .violet
                )

                if vm.isLoadingCommunities {
                    TorpilleLoadingView().frame(maxWidth: .infinity).padding()
                }
                if vm.communities.isEmpty && !vm.isLoadingCommunities {
                    ContentUnavailableView(languageService.phrase("Aucune communauté"), systemImage: "person.3.sequence.fill", description: Text(languageService.phrase("Crée ta première communauté pour commencer à jouer.")))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                } else {
                    ForEach(vm.orderedCommunities, id: \.stableId) { community in
                        Button {
                            onOpenCommunity(community.stableId)
                        } label: {
                            IllustratedActionButton(
                                title: community.name,
                                subtitle: vm.isPinned(community)
                                    ? "\(languageService.phrase(community.isPublic ? "Communauté publique" : "Communauté privée")) · \(languageService.phrase("Épinglée"))"
                                    : languageService.phrase(community.isPublic ? "Communauté publique" : "Communauté privée"),
                                systemImage: community.isPublic ? "person.2.wave.2.fill" : "lock.fill",
                                illustrationSymbol: "flag.2.crossed.fill",
                                accent: community.isPublic ? .meadow : .berry,
                                trailingText: vm.isPinned(community) ? languageService.phrase("Épinglée") : nil
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(languageService.phrase(vm.isPinned(community) ? "Retirer de l’accueil" : "Épingler dans l’accueil")) {
                                vm.togglePinnedCommunity(community)
                            }
                        }
                    }
                }

                if let info = vm.infoMessage {
                    Text(info)
                        .foregroundStyle(.green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let error = vm.error {
                    Text(languageService.localizedRuntimeMessage(error))
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(languageService.text(.communities))
        .reserveMainTabBarSpace()
        .onAppear { vm.start() }
        .navigationDestination(isPresented: Binding(
            get: { vm.selectedPublicProfile != nil },
            set: { if !$0 { vm.selectedPublicProfile = nil } }
        )) {
            if let profile = vm.selectedPublicProfile {
                SharedPublicUserProfileView(profile: profile)
            }
        }
    }
}

struct UserProfileScreen: View {
    @StateObject private var vm: HomeViewModel
    @ObservedObject private var languageService: AppLanguageService
    @State private var firstNameDraft = ""
    @State private var lastNameDraft = ""
    @State private var pseudoDraft = ""
    @State private var birthDateDraft: Date?
    @State private var sexDraft: ProfileSex?
    @State private var hasLoadedSexDraft = false
    @State private var cityDraft = ""
    @State private var bioDraft = ""
    @State private var acceptsTermsDraft = false
    @State private var selectedPhotoData: Data?
    @State private var selectedProfileIcon = "🎯"
    @State private var isSavingProfile = false
    @State private var isShowingSignOutConfirmation = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isLanguagePublic = true
    @State private var isLeaderboardPublic = true
    @State private var isShowingFriends = false
    @State private var isShowingPublicInformationSettings = false
    @State private var showsPasswordResetInfoNearButton = false
    @State private var blockedUserPendingUnblock: BlockedUser?

    let onEditProfile: () -> Void
    let onOpenGlobalLeaderboard: () -> Void
    let onSignOut: () -> Void
    let onBack: (() -> Void)?

    init(env: AppEnvironment, onEditProfile: @escaping () -> Void, onOpenGlobalLeaderboard: @escaping () -> Void, onSignOut: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.onEditProfile = onEditProfile
        self.onOpenGlobalLeaderboard = onOpenGlobalLeaderboard
        self.onSignOut = onSignOut
        self.onBack = onBack
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository, languageService: env.languageService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProfileHeroBanner(
                    title: languageService.text(.profileTitle),
                    pseudo: pseudoDraft.isEmpty ? (vm.me?.pseudo ?? "") : pseudoDraft,
                    xpTotal: vm.me?.effectiveTotalXP ?? 0,
                    photoURL: vm.me?.photoUrl,
                    imageData: selectedPhotoData
                )

                profileFormCard

                saveProfileButton

                if let message = vm.profileSaveMessage {
                    profileSaveMessage(message, succeeded: vm.profileSaveSucceeded)
                }

                Button {
                    isShowingPublicInformationSettings = true
                } label: {
                    IllustratedActionButton(
                        title: languageService.phrase("Informations publiques"),
                        subtitle: nil,
                        systemImage: "eye.fill",
                        illustrationSymbol: "person.text.rectangle.fill",
                        accent: .ocean
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isShowingFriends = true
                } label: {
                    IllustratedActionButton(
                        title: languageService.phrase("Amis"),
                        subtitle: "\(vm.friends.count) \(languageService.friendCountWord(vm.friends.count)) · \(languageService.phrase("rechercher par pseudo"))",
                        systemImage: "person.2.fill",
                        illustrationSymbol: "magnifyingglass.circle.fill",
                        accent: .violet
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showsPasswordResetInfoNearButton = true
                    vm.resetPassword()
                } label: {
                    IllustratedActionButton(
                        title: languageService.text(.resetPassword),
                        subtitle: nil,
                        systemImage: "key.fill",
                        illustrationSymbol: "envelope.badge.fill",
                        accent: .gold
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageService.text(.resetPassword))

                if showsPasswordResetInfoNearButton, let info = vm.infoMessage {
                    profileInfoMessage(info, alreadyLocalized: true)
                }

                Button(action: onOpenGlobalLeaderboard) {
                    IllustratedActionButton(
                        title: languageService.text(.viewGlobalLeaderboard),
                        subtitle: nil,
                        systemImage: "trophy.fill",
                        illustrationSymbol: "chart.bar.fill",
                        accent: .ocean
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageService.text(.viewGlobalLeaderboard))

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitleView(
                        title: languageService.phrase("Informations légales et assistance"),
                        subtitle: languageService.phrase("Consulte les informations sur tes données ou contacte directement Torpille.")
                    )
                    Link(destination: AppExternalLinks.privacyPolicy(language: languageService.effectiveLanguage)) {
                        Label(languageService.phrase("Politique de confidentialité"), systemImage: "hand.raised.fill")
                    }
                    Link(destination: AppExternalLinks.support) {
                        Label(languageService.phrase("Support et contact"), systemImage: "envelope.fill")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitleView(
                        title: languageService.phrase("Utilisateurs bloqués"),
                        subtitle: languageService.phrase("Les utilisateurs bloqués disparaissent des communautés partagées, des fils et de la carte.")
                    )

                    if vm.blockedUsers.isEmpty {
                        Text(languageService.phrase("Aucun utilisateur bloqué."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.blockedUsers) { blockedUser in
                            HStack(spacing: 12) {
                                if let icon = blockedUser.profileIcon, !icon.isEmpty {
                                    EmojiAvatarView(profileIcon: icon, size: 38)
                                } else {
                                    ProfileAvatarImageView(
                                        imageData: nil,
                                        photoURL: blockedUser.photoUrl,
                                        fallbackSymbol: "person.crop.circle.fill",
                                        size: 38
                                    )
                                }

                                Text("@\(blockedUser.pseudo.isEmpty ? blockedUser.id : blockedUser.pseudo)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button(languageService.phrase("Débloquer")) {
                                    showsPasswordResetInfoNearButton = false
                                    blockedUserPendingUnblock = blockedUser
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    isShowingSignOutConfirmation = true
                } label: {
                    IllustratedActionButton(
                        title: languageService.text(.signOut),
                        subtitle: nil,
                        systemImage: "rectangle.portrait.and.arrow.right",
                        illustrationSymbol: "door.right.hand.open",
                        accent: .coral
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageService.text(.signOut))

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    IllustratedActionButton(
                        title: vm.isDeletingAccount ? languageService.text(.deleteAccountProgress) : languageService.text(.deleteAccount),
                        subtitle: nil,
                        systemImage: "trash.fill",
                        illustrationSymbol: "person.crop.circle.badge.xmark",
                        accent: .coral
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isDeletingAccount)
                .accessibilityLabel(vm.isDeletingAccount ? languageService.text(.deleteAccountProgress) : languageService.text(.deleteAccount))

            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(languageService.text(.profile))
        .iosBackSwipe(enabled: onBack != nil) {
            onBack?()
        }
        .reserveMainTabBarSpace()
        .onAppear {
            vm.start()
            loadProfileDraftsIfNeeded()
            selectedProfileIcon = vm.me?.profileIcon ?? selectedProfileIcon
            isLanguagePublic = vm.me?.isLanguagePublic ?? true
            isLeaderboardPublic = vm.me?.isLeaderboardPublic ?? true
            selectedPhotoData = nil
        }
        .onChange(of: vm.me?.pseudo ?? "") { _, newValue in
            if !newValue.isEmpty, pseudoDraft.isEmpty {
                loadProfileDraftsIfNeeded()
            }
        }
        .alert(languageService.phrase("Se déconnecter ?"), isPresented: $isShowingSignOutConfirmation) {
            Button(languageService.phrase("Annuler"), role: .cancel) {}
            Button(languageService.text(.signOut), role: .destructive) {
                vm.signOut(onDone: onSignOut)
            }
        } message: {
            Text(languageService.phrase("Tu devras te reconnecter pour accéder à ton compte."))
        }
        .alert(languageService.phrase("Supprimer ce compte ?"), isPresented: $isShowingDeleteConfirmation) {
            Button(languageService.phrase("Annuler"), role: .cancel) {}
            Button(languageService.phrase("Supprimer"), role: .destructive) {
                vm.deleteAccount(onDone: onSignOut)
            }
        } message: {
            Text(languageService.phrase("Cette action est définitive. Ton profil, tes préférences et tes communautés administrées seront supprimés."))
        }
        .alert(
            languageService.phrase("Débloquer cet utilisateur ?"),
            isPresented: Binding(
                get: { blockedUserPendingUnblock != nil },
                set: { if !$0 { blockedUserPendingUnblock = nil } }
            )
        ) {
            Button(languageService.phrase("Annuler"), role: .cancel) {
                blockedUserPendingUnblock = nil
            }
            Button(languageService.phrase("Débloquer"), role: .destructive) {
                if let blockedUser = blockedUserPendingUnblock {
                    vm.unblockUser(blockedUser)
                }
                blockedUserPendingUnblock = nil
            }
        } message: {
            let displayName = blockedUserPendingUnblock.map { "@\($0.pseudo.isEmpty ? $0.id : $0.pseudo)" } ?? languageService.phrase("cet utilisateur")
            Text("\(displayName) \(languageService.phrase("réapparaîtra dans les communautés partagées, les fils et la carte."))")
        }
        .sheet(isPresented: $isShowingFriends) {
            FriendsSheet(vm: vm)
        }
        .navigationDestination(isPresented: $isShowingPublicInformationSettings) {
            PublicInformationSettingsScreen(
                vm: vm,
                languageService: languageService,
                isLanguagePublic: $isLanguagePublic,
                isLeaderboardPublic: $isLeaderboardPublic
            )
        }
    }

    private var profileLanguagePicker: some View {
        Picker(languageService.text(.appLanguage), selection: $languageService.language) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.nativeLabel).tag(language)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var saveProfileButton: some View {
        Button {
            Task {
                showsPasswordResetInfoNearButton = false
                isSavingProfile = true
                let didSave = await vm.saveProfile(
                    firstName: firstNameDraft,
                    lastName: lastNameDraft,
                    pseudo: pseudoDraft,
                    birthDate: birthDateDraft,
                    sex: sexDraft,
                    city: cityDraft,
                    bio: bioDraft,
                    imageData: selectedPhotoData,
                    profileIcon: selectedPhotoData == nil ? selectedProfileIcon : nil,
                    acceptsTerms: acceptsTermsDraft
                )
                isSavingProfile = false
                if didSave {
                    selectedPhotoData = nil
                    onEditProfile()
                }
            }
        } label: {
            IllustratedActionButton(
                title: isSavingProfile ? languageService.text(.saving) : languageService.text(.saveProfile),
                subtitle: nil,
                systemImage: "square.and.arrow.down.fill",
                illustrationSymbol: "checkmark.seal.fill",
                accent: .meadow
            )
        }
        .buttonStyle(.plain)
        .disabled(isSavingProfile)
        .accessibilityLabel(isSavingProfile ? languageService.phrase("Enregistrement en cours") : languageService.text(.saveProfile))
    }

    private func profileInfoMessage(_ info: String, alreadyLocalized: Bool = false) -> some View {
        Text(alreadyLocalized ? info : languageService.localizedRuntimeMessage(info))
            .foregroundStyle(.green)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func profileSaveMessage(_ message: String, succeeded: Bool) -> some View {
        let color: Color = succeeded ? .green : .red
        return Text(languageService.localizedRuntimeMessage(message))
            .foregroundStyle(color)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var profileFormCard: some View {
        VStack(spacing: 16) {
            if let missingFields = vm.me?.missingRequiredProfileFields, !missingFields.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(languageService.phrase("Profil à compléter"))
                        .font(.headline)
                    Text(languageService.phrase("Obligatoire pour créer ou rejoindre une communauté :") + " " + missingFields.joined(separator: ", ") + ".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack {
                Spacer()
                ProfileAvatarView(
                    photoURL: vm.me?.photoUrl,
                    profileIcon: selectedProfileIcon,
                    imageData: selectedPhotoData
                )
                Spacer()
            }

            ProfilePhotoPicker(selectedImageData: $selectedPhotoData)

            if selectedPhotoData == nil && vm.me?.photoUrl?.isEmpty != false {
                ProfileIconPicker(selectedIcon: $selectedProfileIcon)
            }

            Text(languageService.phrase("Informations obligatoires"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(languageService.phrase("Prénom"), text: $firstNameDraft)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TextField(languageService.phrase("Nom de famille"), text: $lastNameDraft)
                .textContentType(.familyName)
                .textInputAutocapitalization(.words)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TextField(languageService.text(.profilePseudoPlaceholder), text: $pseudoDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if vm.me?.termsAcceptedAt == nil || vm.me?.moderationRulesAcceptedAt == nil {
                Toggle(languageService.phrase("J’accepte les règles EULA"), isOn: $acceptsTermsDraft)
            }

            Text(languageService.phrase("Informations facultatives"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProfileSexPicker(selection: $sexDraft)

            Toggle(languageService.phrase("Ajouter ma date de naissance"), isOn: Binding(
                get: { birthDateDraft != nil },
                set: { birthDateDraft = $0 ? Calendar.current.date(byAdding: .year, value: -18, to: Date()) : nil }
            ))

            if birthDateDraft != nil {
                DatePicker(
                    languageService.phrase("Date de naissance"),
                    selection: Binding(get: { birthDateDraft ?? Date() }, set: { birthDateDraft = $0 }),
                    in: ...Date(),
                    displayedComponents: .date
                )
            }

            TextField(languageService.phrase("Ville de domiciliation"), text: $cityDraft)
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            TextField(languageService.phrase("Courte présentation"), text: $bioDraft, axis: .vertical)
                .lineLimit(2...4)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            infoRow(title: languageService.text(.profileEmail), value: vm.email, symbol: "envelope.fill")

            profileLanguagePicker
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func loadProfileDraftsIfNeeded() {
        guard let profile = vm.me else { return }
        if firstNameDraft.isEmpty { firstNameDraft = profile.firstName }
        if lastNameDraft.isEmpty { lastNameDraft = profile.lastName }
        if pseudoDraft.isEmpty { pseudoDraft = profile.pseudo }
        if cityDraft.isEmpty { cityDraft = profile.city ?? "" }
        if bioDraft.isEmpty { bioDraft = profile.bio ?? "" }
        if birthDateDraft == nil { birthDateDraft = profile.birthDate?.dateValue() }
        if !hasLoadedSexDraft {
            sexDraft = profile.sex
            hasLoadedSexDraft = true
        }
        acceptsTermsDraft = profile.termsAcceptedAt != nil && profile.moderationRulesAcceptedAt != nil
        selectedProfileIcon = profile.profileIcon ?? selectedProfileIcon
        isLanguagePublic = profile.isLanguagePublic
        isLeaderboardPublic = profile.isLeaderboardPublic
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

private struct PublicInformationSettingsScreen: View {
    @ObservedObject var vm: HomeViewModel
    @ObservedObject var languageService: AppLanguageService
    @Binding var isLanguagePublic: Bool
    @Binding var isLeaderboardPublic: Bool

    var body: some View {
        List {
            Section {
                publicInfoRow("Pseudo", isAlwaysPublic: true)
                publicInfoRow("Photo de profil", isAlwaysPublic: true)
                publicInfoRow("Nombre d'amis", isAlwaysPublic: true)
            } header: {
                Text(languageService.phrase("Toujours public"))
            } footer: {
                Text(languageService.phrase("Ces informations permettent aux membres de communautés partagées de t'identifier et de demander à devenir ami."))
            }

            Section {
                Toggle(languageService.phrase("Afficher ma langue"), isOn: $isLanguagePublic)
                Toggle(languageService.phrase("Afficher mon classement global"), isOn: $isLeaderboardPublic)
            } header: {
                Text(languageService.phrase("Visibilité optionnelle"))
            } footer: {
                Text(languageService.phrase("Tu peux masquer ta langue et ton classement global à tout moment."))
            }

            Section {
                Button {
                    vm.savePublicSettings(
                        languageCode: languageService.effectiveLanguage.rawValue,
                        isLanguagePublic: isLanguagePublic,
                        isLeaderboardPublic: isLeaderboardPublic
                    )
                } label: {
                    Label(languageService.phrase("Enregistrer la visibilité"), systemImage: "checkmark.seal.fill")
                }
            }

            if let info = vm.infoMessage {
                Section {
                    Text(info)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(languageService.phrase("Informations publiques"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isLanguagePublic = vm.me?.isLanguagePublic ?? isLanguagePublic
            isLeaderboardPublic = vm.me?.isLeaderboardPublic ?? isLeaderboardPublic
        }
    }

    private func publicInfoRow(_ title: String, isAlwaysPublic: Bool) -> some View {
        HStack {
            Image(systemName: isAlwaysPublic ? "eye.fill" : "eye")
                .foregroundStyle(ActionAccent.ocean.tint)
            Text(languageService.phrase(title))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(languageService.phrase(isAlwaysPublic ? "Toujours public" : "Optionnel"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FriendsSheet: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var languageService: AppLanguageService
    @State private var query = ""
    @State private var profilePendingFriendRequest: UserProfile?
    @State private var friendPendingRemoval: PublicFriend?
    @State private var requestResultMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if vm.friends.isEmpty {
                        Text(languageService.phrase("Aucun ami pour le moment."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.friends) { friend in
                            friendRow(friend)
                        }
                    }
                } header: {
                    Text(languageService.phrase("Mes amis"))
                } footer: {
                    Text(languageService.phrase("Le nombre d'amis est toujours visible publiquement."))
                }

                Section {
                    TextField(languageService.phrase("Rechercher un pseudo"), text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in
                            vm.searchFriends(query: newValue)
                        }

                    if vm.isSearchingFriends {
                        TorpilleLoadingView()
                    }

                    ForEach(vm.friendSearchResults) { profile in
                        HStack(spacing: 12) {
                            if let icon = profile.profileIcon, !icon.isEmpty {
                                EmojiAvatarView(profileIcon: icon, size: 42)
                            } else {
                                ProfileAvatarImageView(
                                    imageData: nil,
                                    photoURL: profile.photoUrl,
                                    fallbackSymbol: "person.fill",
                                    size: 42
                                )
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("@\(profile.pseudo)")
                                    .font(.headline)
                                SharedPublicProfileSummary(profile: profile, friendsCount: profile.friendsCount)
                            }
                            Spacer()
                            if vm.friends.contains(where: { $0.uid == profile.uid }) {
                                Label(languageService.phrase("Ami"), systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button(languageService.phrase("Ajouter")) {
                                    profilePendingFriendRequest = profile
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.selectedPublicProfile = profile
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(languageService.phrase("Rechercher un utilisateur"))
                } footer: {
                    Text(languageService.phrase("Ouvre ton profil, va dans Amis, puis recherche le pseudo de la personne à ajouter."))
                }
            }
            .navigationTitle(languageService.phrase("Amis"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageService.phrase("Fermer")) { dismiss() }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { vm.selectedPublicProfile != nil },
                set: { if !$0 { vm.selectedPublicProfile = nil } }
            )) {
                if let profile = vm.selectedPublicProfile {
                    SharedPublicUserProfileView(profile: profile) {
                        profilePendingFriendRequest = profile
                    }
                }
            }
            .alert(
                languageService.phrase("Envoyer une demande d'ami ?"),
                isPresented: Binding(
                    get: { profilePendingFriendRequest != nil },
                    set: { if !$0 { profilePendingFriendRequest = nil } }
                )
            ) {
                Button(languageService.phrase("Annuler"), role: .cancel) {
                    profilePendingFriendRequest = nil
                }
                Button(languageService.phrase("Envoyer")) {
                    guard let profile = profilePendingFriendRequest else { return }
                    profilePendingFriendRequest = nil
                    Task {
                        let succeeded = await vm.sendFriendRequestAndWait(to: profile)
                        requestResultMessage = succeeded ? vm.infoMessage : vm.error
                    }
                }
            } message: {
                Text(languageService.localizedFriendRequestConfirmation(pseudo: profilePendingFriendRequest?.pseudo ?? ""))
            }
            .alert(
                languageService.phrase("Demande d'ami"),
                isPresented: Binding(
                    get: { requestResultMessage != nil },
                    set: { if !$0 { requestResultMessage = nil } }
                )
            ) {
                Button(languageService.phrase("OK")) { requestResultMessage = nil }
            } message: {
                Text(languageService.localizedRuntimeMessage(requestResultMessage ?? ""))
            }
            .alert(
                languageService.phrase("Supprimer cet ami ?"),
                isPresented: Binding(
                    get: { friendPendingRemoval != nil },
                    set: { if !$0 { friendPendingRemoval = nil } }
                )
            ) {
                Button(languageService.phrase("Annuler"), role: .cancel) {
                    friendPendingRemoval = nil
                }
                Button(languageService.phrase("Supprimer"), role: .destructive) {
                    guard let friend = friendPendingRemoval else { return }
                    friendPendingRemoval = nil
                    Task {
                        let succeeded = await vm.removeFriendAndWait(friend)
                        requestResultMessage = succeeded ? vm.infoMessage : vm.error
                    }
                }
            } message: {
                Text(languageService.localizedFriendRemovalConfirmation(pseudo: friendPendingRemoval?.pseudo ?? ""))
            }
        }
    }

    private func friendRow(_ friend: PublicFriend) -> some View {
        HStack(spacing: 12) {
            if let profileIcon = friend.profileIcon, !profileIcon.isEmpty {
                EmojiAvatarView(profileIcon: profileIcon, size: 42)
            } else {
                ProfileAvatarImageView(
                    imageData: nil,
                    photoURL: friend.photoUrl,
                    fallbackSymbol: "person.fill",
                    size: 42
                )
            }
            Text("@\(friend.pseudo)")
                .font(.headline)
            Spacer()
            Button(role: .destructive) {
                friendPendingRemoval = friend
            } label: {
                Image(systemName: "person.badge.minus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(languageService.phrase("Supprimer cet ami"))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.openPublicProfile(for: friend)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(languageService.phrase("Ouvre le profil public de cet ami."))
    }
}

struct SharedPublicUserProfileView: View {
    let profile: UserProfile
    var onAddFriend: (() -> Void)? = nil
    @EnvironmentObject private var languageService: AppLanguageService
    @StateObject private var memoriesVM: PublicProfileMemoriesViewModel
    @State private var playbackURL: URL?
    @State private var playbackReel: PublishedReel?

    init(profile: UserProfile, onAddFriend: (() -> Void)? = nil) {
        self.profile = profile
        self.onAddFriend = onAddFriend
        _memoriesVM = StateObject(wrappedValue: PublicProfileMemoriesViewModel(authorUid: profile.id))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                publicProfileAvatar

                VStack(spacing: 8) {
                    Text("@\(profile.pseudo)")
                        .font(.title2.bold())
                    SharedPublicProfileSummary(profile: profile, friendsCount: profile.friendsCount)
                }

                Text(languageService.phrase("Le pseudo, la photo de profil et le nombre d'amis sont publics. La langue et le classement ne s'affichent ici que si l'utilisateur les a rendus visibles."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let onAddFriend {
                    Button {
                        onAddFriend()
                    } label: {
                        Label(languageService.phrase("Envoyer une demande d'ami"), systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }

                publicMemoriesSection
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle(languageService.phrase("Profil public"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memoriesVM.start() }
        .onDisappear { memoriesVM.stop() }
        .sheet(item: Binding(get: {
            playbackURL.map { PlaybackContainer(url: $0, mediaType: .video, title: playbackReel?.taggedPseudo, sender: playbackReel?.authorPseudo, tagX: nil, tagY: nil) }
        }, set: { newValue in
            if newValue == nil {
                playbackURL = nil
                playbackReel = nil
            }
        })) { item in
            VideoPlayerSheet(
                url: item.url,
                mediaType: item.mediaType,
                overlayText: item.title,
                authorPseudo: item.sender,
                authorPhotoUrl: playbackReel?.authorPhotoUrl ?? profile.photoUrl,
                authorProfileIcon: playbackReel?.authorProfileIcon ?? profile.profileIcon,
                tagX: nil,
                tagY: nil
            )
        }
    }

    @ViewBuilder
    private var publicProfileAvatar: some View {
        if profile.photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            ProfileAvatarImageView(
                imageData: nil,
                photoURL: profile.photoUrl,
                fallbackSymbol: "person.crop.circle.fill",
                size: 112
            )
        } else if let profileIcon = profile.profileIcon,
                  !profileIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmojiAvatarView(profileIcon: profileIcon, size: 112)
        } else {
            ProfileAvatarImageView(
                imageData: nil,
                photoURL: nil,
                fallbackSymbol: "person.crop.circle.fill",
                size: 112
            )
        }
    }

    @ViewBuilder
    private var publicMemoriesSection: some View {
        if !memoriesVM.reels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(languageService.text(.reelsTitle))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                ForEach(memoriesVM.reels, id: \.stableId) { reel in
                    Button {
                        open(reel)
                    } label: {
                        PublicProfileMemoryRow(reel: reel)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }

    private func open(_ reel: PublishedReel) {
        Task {
            do {
                playbackURL = try await memoriesVM.resolvePlaybackURL(for: reel)
                playbackReel = reel
            } catch {
                memoriesVM.error = error.localizedDescription
            }
        }
    }
}

private struct PublicProfileMemoryRow: View {
    let reel: PublishedReel
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ActionAccent.coral.tint.opacity(0.14))
                Image(systemName: "play.rectangle.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ActionAccent.coral.tint)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(reel.communityName.isEmpty ? languageService.text(.reelsTitle) : reel.communityName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let taggedPseudo = reel.taggedPseudo, !taggedPseudo.isEmpty {
                    Text("→ @\(taggedPseudo)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let publishedAt = reel.publishedAt?.dateValue() {
                    Text(publishedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ActionAccent.coral.gradient)
                .clipShape(Circle())
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@MainActor
final class PublicProfileMemoriesViewModel: ObservableObject {
    @Published var reels: [PublishedReel] = []
    @Published var error: String?

    private let authorUid: String
    private let db = Firestore.firestore()
    private var registration: ListenerRegistration?

    init(authorUid: String) {
        self.authorUid = authorUid
    }

    func start() {
        stop()
        let cleanAuthorUid = authorUid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAuthorUid.isEmpty else { return }

        registration = db.collection("reels")
            .whereField("authorUid", isEqualTo: cleanAuthorUid)
            .addSnapshotListener { [weak self] snapshot, _ in
                let values = snapshot?.documents.compactMap { document -> PublishedReel? in
                    var reel = try? document.data(as: PublishedReel.self)
                    reel?.id = document.documentID
                    return reel
                } ?? []

                DispatchQueue.main.async {
                    self?.reels = values
                        .filter { !$0.isQuarantined }
                        .sorted { ($0.publishedAt?.dateValue() ?? .distantPast) > ($1.publishedAt?.dateValue() ?? .distantPast) }
                }
            }
    }

    func stop() {
        registration?.remove()
        registration = nil
    }

    func resolvePlaybackURL(for reel: PublishedReel) async throws -> URL {
        if let rawURL = reel.videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawURL.isEmpty,
           let url = URL(string: rawURL) {
            return url
        }

        guard let rawPath = reel.videoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            throw TorpilleError.videoNotAvailable
        }

        let storageReference: StorageReference
        if let bucket = reel.videoBucket?.trimmingCharacters(in: .whitespacesAndNewlines), !bucket.isEmpty {
            storageReference = Storage.storage(url: "gs://\(bucket)").reference(withPath: rawPath)
        } else {
            storageReference = Storage.storage().reference(withPath: rawPath)
        }
        return try await storageReference.downloadURL()
    }

    deinit {
        registration?.remove()
    }
}

struct SharedPublicProfileSummary: View {
    let profile: UserProfile
    let friendsCount: Int?
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if profile.isLanguagePublic, let languageCode = profile.languageCode, !languageCode.isEmpty {
                Text("\(languageService.text(.language)) : \(languageCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if profile.isLeaderboardPublic {
                Text("\(languageService.phrase("Classement global")) : \(profile.effectiveTotalXP) XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let friendsCount {
                Text(languageService.friendCountLabel(friendsCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileAvatarView: View {
    let photoURL: String?
    let profileIcon: String?
    let imageData: Data?

    var body: some View {
        if imageData == nil,
           photoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let profileIcon,
           !profileIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmojiAvatarView(profileIcon: profileIcon, size: 104)
        } else {
            ProfileAvatarImageView(
                imageData: imageData,
                photoURL: photoURL,
                fallbackSymbol: "person.crop.circle.fill",
                size: 104
            )
        }
    }
}


struct GlobalLeaderboardScreen: View {
    @StateObject private var vm: GlobalLeaderboardViewModel
    @ObservedObject private var languageService: AppLanguageService
    let onBack: (() -> Void)?

    init(env: AppEnvironment, onBack: (() -> Void)? = nil) {
        self.onBack = onBack
        _languageService = ObservedObject(wrappedValue: env.languageService)
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
                    title: languageService.phrase("Classement global"),
                    subtitle: nil,
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
        .navigationTitle(languageService.text(.leaderboard))
        .iosBackSwipe(enabled: onBack != nil) {
            onBack?()
        }
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button(languageService.phrase("Retour"), action: onBack)
                }
            }
        }
        .reserveMainTabBarSpace()
        .onAppear { vm.start() }
        .navigationDestination(isPresented: Binding(
            get: { vm.selectedPublicProfile != nil },
            set: { if !$0 { vm.selectedPublicProfile = nil } }
        )) {
            if let profile = vm.selectedPublicProfile {
                SharedPublicUserProfileView(profile: profile)
            }
        }
    }

    private var filtersSection: some View {
        Section(languageService.phrase("Filtres")) {
            Button {
                vm.clearCommunityFilters()
            } label: {
                CompactActionButton(
                    title: languageService.phrase(!vm.hasActiveCommunityFilter ? "Classement total activé" : "Revenir au classement total"),
                    systemImage: "line.3.horizontal.decrease.circle.fill",
                    accent: .ocean
                )
            }
            .buttonStyle(.plain)

            if vm.availableCommunities.isEmpty {
                Text(languageService.phrase("Rejoins une ou plusieurs communautés pour filtrer le classement."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.availableCommunities, id: \.stableId) { community in
                    Button {
                        vm.toggleCommunity(community.stableId)
                    } label: {
                        CompactActionButton(
                            title: vm.selectedCommunityIds.contains(community.stableId) ? languageService.selectedCommunityLabel(community.name) : community.name,
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
                languageService.phrase("Aucun joueur"),
                systemImage: "person.3.sequence.fill",
                description: Text(languageService.phrase("Le classement sera visible dès qu'il y aura des profils à comparer."))
            )
        }
    }

    private var leaderboardSection: some View {
        Section(languageService.phrase("Joueurs")) {
            ForEach(Array(vm.players.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: 12) {
                    Text("#\(index + 1)")
                        .font(.headline)
                        .frame(width: 46, height: 46)
                        .background((index == 0 ? ActionAccent.gold.tint : ActionAccent.ocean.tint).opacity(0.14))
                        .clipShape(Circle())

                    Button {
                        vm.openPublicProfile(player)
                    } label: {
                        if let profileIcon = player.profileIcon, !profileIcon.isEmpty {
                            EmojiAvatarView(profileIcon: profileIcon, size: 42)
                        } else {
                            ProfileAvatarImageView(
                                imageData: nil,
                                photoURL: player.photoUrl,
                                fallbackSymbol: "person.fill",
                                size: 42
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.pseudo)
                            .font(.headline)
                        Text(languageService.xpInCommunityLabel(Int64(vm.displayedXP(for: player))))
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
    @ObservedObject private var languageService: AppLanguageService
    @State private var isShowingCommunityPreferences = false
    let onBack: () -> Void

    init(env: AppEnvironment, onBack: @escaping () -> Void) {
        _notificationService = ObservedObject(wrappedValue: env.notificationCenterService)
        _languageService = ObservedObject(wrappedValue: env.languageService)
        self.onBack = onBack
    }

    var body: some View {
        List {
            Section {
                Button {
                    isShowingCommunityPreferences = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(ActionAccent.ocean.tint)
                            .frame(width: 36, height: 36)
                            .background(ActionAccent.ocean.tint.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(languageService.phrase("Préférences par communauté"))
                                .font(.headline)
                            Text(languageService.phrase("Choisir quand chaque communauté peut te notifier."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } header: {
                Text(languageService.phrase("Réglages"))
            }

            Section {
                if !notificationService.communityJoinRequests.isEmpty {
                    ForEach(notificationService.communityJoinRequests) { request in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                if let icon = request.requesterProfileIcon, !icon.isEmpty {
                                    EmojiAvatarView(profileIcon: icon, size: 42)
                                } else {
                                    ProfileAvatarImageView(
                                        imageData: nil,
                                        photoURL: request.requesterPhotoUrl,
                                        fallbackSymbol: "person.fill",
                                        size: 42
                                    )
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(request.requesterPseudo.isEmpty ? languageService.phrase("Utilisateur") : "@\(request.requesterPseudo)")
                                        .font(.headline)
                                    Text(languageService.communityJoinRequestBody(communityName: request.communityName))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button(languageService.phrase("Refuser"), role: .destructive) {
                                    notificationService.resolveCommunityJoinRequest(request, accept: false)
                                }
                                .buttonStyle(.bordered)
                                Button(languageService.phrase("Accepter")) {
                                    notificationService.resolveCommunityJoinRequest(request, accept: true)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !notificationService.friendRequests.isEmpty {
                    ForEach(notificationService.friendRequests) { request in
                        HStack(spacing: 12) {
                            if let icon = request.fromProfileIcon, !icon.isEmpty {
                                EmojiAvatarView(profileIcon: icon, size: 42)
                            } else {
                                ProfileAvatarImageView(
                                    imageData: nil,
                                    photoURL: request.fromPhotoUrl,
                                    fallbackSymbol: "person.fill",
                                    size: 42
                                )
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("@\(request.fromPseudo)")
                                    .font(.headline)
                                Text(languageService.phrase("veut devenir ami avec toi."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(languageService.phrase("Refuser")) {
                                notificationService.rejectFriendRequest(request)
                            }
                            .buttonStyle(.bordered)
                            Button(languageService.phrase("Accepter")) {
                                notificationService.acceptFriendRequest(request)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                }

                if notificationService.items.isEmpty
                    && notificationService.friendRequests.isEmpty
                    && notificationService.communityJoinRequests.isEmpty {
                    ContentUnavailableView(
                        languageService.phrase("Aucune notification"),
                        systemImage: "bell.slash",
                        description: Text(languageService.phrase("Les nouvelles notifications reçues apparaîtront ici."))
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(notificationService.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            if item.id.hasPrefix("torpille_") {
                                HStack(alignment: .top) {
                                    Text(item.body)
                                        .font(.headline)
                                    Spacer()
                                    if !item.isRead {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 10, height: 10)
                                    }
                                }
                            } else {
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
                            }
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
                                Label(languageService.phrase("Supprimer"), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text(languageService.phrase("Activité et demandes"))
            }

            Section {
                Text(languageService.phrase("Les notifications sont automatiquement supprimées après deux semaines."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(languageService.phrase("Activité"))
        .sheet(isPresented: $isShowingCommunityPreferences) {
            CommunityNotificationPreferencesSheet(notificationService: notificationService)
        }
        .iosBackSwipe {
            onBack()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(languageService.phrase("Retour"), action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !notificationService.items.isEmpty {
                    Button(languageService.phrase("Tout lu")) {
                        notificationService.markAllAsRead()
                    }
                }
            }
        }
        .onAppear {
            notificationService.start()
        }
    }
}

private struct CommunityNotificationPreferencesSheet: View {
    @ObservedObject var notificationService: NotificationCenterService
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(notificationService.communities, id: \.stableId) { community in
                        let preference = notificationService.preference(for: community)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(community.name)
                                .font(.headline)
                            Picker(languageService.phrase("Notifications"), selection: Binding(
                                get: { preference.mode },
                                set: { notificationService.updatePreference(for: community, mode: $0) }
                            )) {
                                ForEach(CommunityNotificationMode.allCases) { mode in
                                    Text(languageService.phrase(mode.title)).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    }

                    if notificationService.communities.isEmpty {
                        ContentUnavailableView(
                            languageService.phrase("Aucune communauté"),
                            systemImage: "person.3.sequence.fill",
                            description: Text(languageService.phrase("Rejoins ou crée une communauté pour configurer tes notifications."))
                        )
                        .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text(languageService.phrase("Notifications"))
                } footer: {
                    Text(languageService.phrase("Choisis si chaque communauté doit te notifier pour tous les contenus ou seulement quand tu es identifié·e."))
                }
            }
            .navigationTitle(languageService.phrase("Préférences"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageService.phrase("Fermer")) { dismiss() }
                }
            }
        }
    }
}
