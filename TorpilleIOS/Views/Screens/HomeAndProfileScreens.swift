import SwiftUI

struct HomeScreen: View {
    @StateObject private var vm: HomeViewModel
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onOpenGlobalLeaderboard: () -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onOpenGlobalLeaderboard: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
        self.onOpenGlobalLeaderboard = onOpenGlobalLeaderboard
        self.onSignOut = onSignOut
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.me?.pseudo ?? "Utilisateur")
                        .font(.headline)
                    Text(vm.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("XP total : \(vm.me?.xpTotal ?? 0)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Créer une communauté", action: onCreateCommunity)
                Button("Classement global", action: onOpenGlobalLeaderboard)
                Button("Déconnexion") {
                    vm.signOut(onDone: onSignOut)
                }
            }

            Section("Mes communautés") {
                ForEach(vm.communities, id: \.stableId) { community in
                    Button {
                        onOpenCommunity(community.stableId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(community.name).font(.headline)
                            Text(community.isPublic ? "Publique" : "Privée")
                                .font(.subheadline)
                            Text("Temps de réponse : \(community.responseTimeSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accueil")
        .onAppear { vm.start() }
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
        List {
            Button("Créer une communauté", action: onCreateCommunity)
            ForEach(vm.communities, id: \.stableId) { community in
                Button(community.name) {
                    onOpenCommunity(community.stableId)
                }
            }
        }
        .navigationTitle("Communautés")
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
        Form {
            Section("Photo de profil") {
                HStack {
                    Spacer()
                    ProfileAvatarView(photoURL: vm.me?.photoUrl, imageData: selectedPhotoData)
                    Spacer()
                }

                ProfilePhotoPicker(selectedImageData: $selectedPhotoData)
            }

            Section("Profil") {
                TextField("Pseudo", text: $pseudoDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("Email : \(vm.email)")

                HStack {
                    Text("Mot de passe")
                    Spacer()
                    Text("••••••••")
                        .foregroundStyle(.secondary)
                }

                Text("Le mot de passe actuel ne peut pas être relu depuis Firebase Auth. Tu peux toutefois le réinitialiser par email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isSavingProfile ? "Enregistrement…" : "Enregistrer les modifications") {
                    Task {
                        isSavingProfile = true
                        let didSave = await vm.saveProfile(pseudo: pseudoDraft, imageData: selectedPhotoData, profileIcon: nil)
                        isSavingProfile = false
                        if didSave {
                            selectedPhotoData = nil
                            onEditProfile()
                        }
                    }
                }
                .disabled(isSavingProfile)

                Button("Réinitialiser le mot de passe") {
                    vm.resetPassword()
                }

                Button("Voir le classement global", action: onOpenGlobalLeaderboard)
            }

            if let info = vm.infoMessage {
                Section { Text(info).foregroundStyle(.green) }
            }

            if let error = vm.error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button("Déconnexion") {
                    vm.signOut(onDone: onSignOut)
                }
            }
        }
        .navigationTitle("Profil")
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
            filtersSection

            if vm.players.isEmpty {
                emptyStateSection
            } else {
                leaderboardSection
            }
        }
        .navigationTitle("Classement")
        .onAppear { vm.start() }
    }

    private var filtersSection: some View {
        Section("Filtres") {
            Button {
                vm.clearCommunityFilters()
            } label: {
                HStack {
                    Text("Classement total")
                    Spacer()
                    if !vm.hasActiveCommunityFilter {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }

            if vm.availableCommunities.isEmpty {
                Text("Rejoins une ou plusieurs communautés pour filtrer le classement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.availableCommunities, id: \.stableId) { community in
                    Button {
                        vm.toggleCommunity(community.stableId)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(community.name)
                                Text(vm.selectedCommunityIds.contains(community.stableId) ? "Incluse dans le filtre" : "Appuie pour inclure cette communauté")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: vm.selectedCommunityIds.contains(community.stableId) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(vm.selectedCommunityIds.contains(community.stableId) ? .blue : .secondary)
                        }
                    }
                }
            }

            Text(vm.filterDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateSection: some View {
        Section {
            VStack(alignment: .center, spacing: 8) {
                Text("Aucun joueur classé pour le moment.")
                    .font(.headline)
                Text(emptyStateDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var leaderboardSection: some View {
        Section(leaderboardTitle) {
            ForEach(Array(vm.players.indices), id: \.self) { index in
                let player = vm.players[index]
                GlobalLeaderboardRow(
                    player: player,
                    rank: index + 1,
                    isCurrentUser: player.uid == vm.currentUserId,
                    rankColor: rankBackgroundColor(for: index)
                )
            }
        }
    }

    private var leaderboardTitle: String {
        vm.hasActiveCommunityFilter ? "Classement filtré" : "Classement global"
    }

    private var emptyStateDescription: String {
        vm.hasActiveCommunityFilter
            ? "Aucun joueur ne correspond aux communautés sélectionnées."
            : "Le classement global apparaîtra ici dès que des profils auront de l'XP totale."
    }

    private func rankBackgroundColor(for index: Int) -> Color {
        switch index {
        case 0: return .yellow
        case 1: return .gray
        case 2: return .brown
        default: return .blue
        }
    }
}

private struct GlobalLeaderboardRow: View {
    let player: UserProfile
    let rank: Int
    let isCurrentUser: Bool
    let rankColor: Color

    private var displayPseudo: String {
        player.pseudo.isEmpty ? "Utilisateur" : player.pseudo
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor)
                    .frame(width: 36, height: 36)
                Text("\(rank)")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            ProfileAvatarImageView(
                imageData: nil,
                photoURL: player.photoUrl,
                fallbackSymbol: "person.crop.circle.fill",
                size: 46
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayPseudo)
                        .font(.headline)

                    if isCurrentUser {
                        Text("Toi")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text("XP totale : \(player.xpTotal)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
