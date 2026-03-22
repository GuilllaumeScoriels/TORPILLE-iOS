import SwiftUI

struct HomeScreen: View {
    @StateObject private var vm: HomeViewModel
    let onCreateCommunity: () -> Void
    let onOpenCommunity: (String) -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onCreateCommunity: @escaping () -> Void, onOpenCommunity: @escaping (String) -> Void, onSignOut: @escaping () -> Void) {
        self.onCreateCommunity = onCreateCommunity
        self.onOpenCommunity = onOpenCommunity
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
    @State private var selectedProfileIcon = "🍺"

    let onEditProfile: () -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onEditProfile: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onEditProfile = onEditProfile
        self.onSignOut = onSignOut
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository))
    }

    var body: some View {
        Form {
            Section("Icône de profil") {
                HStack {
                    Spacer()
                    ProfileAvatarView(profileIcon: selectedProfileIcon)
                    Spacer()
                }

                ProfileIconPicker(selectedIcon: $selectedProfileIcon)
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

                Button("Enregistrer les modifications") {
                    vm.saveProfile(pseudo: pseudoDraft, imageData: nil, profileIcon: selectedProfileIcon)
                    onEditProfile()
                }

                Button("Réinitialiser le mot de passe") {
                    vm.resetPassword()
                }
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
            selectedProfileIcon = vm.me?.profileIcon ?? selectedProfileIcon
        }
        .onChange(of: vm.me?.pseudo ?? "") { _, newValue in
            if !newValue.isEmpty, pseudoDraft.isEmpty {
                pseudoDraft = newValue
            }
        }
    }
}

private struct ProfileAvatarView: View {
    let profileIcon: String

    var body: some View {
        EmojiAvatarView(profileIcon: profileIcon, size: 104)
    }
}
