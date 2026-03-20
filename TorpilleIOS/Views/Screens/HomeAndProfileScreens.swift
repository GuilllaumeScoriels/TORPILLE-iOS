/**
 Fichier : HomeAndProfileScreens.swift
 Rôle :
 - Affiche l'accueil, l'onglet communautés et l'écran profil.

 Ce que fait ce fichier :
 - Liste les communautés de l'utilisateur.
 - Donne un accès direct à la création de communauté et à la déconnexion.
 - Affiche un bouton carte, comme dans la version Android enrichie.
 */

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
    let onEditProfile: () -> Void
    let onSignOut: () -> Void

    init(env: AppEnvironment, onEditProfile: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onEditProfile = onEditProfile
        self.onSignOut = onSignOut
        _vm = StateObject(wrappedValue: HomeViewModel(authRepository: env.authRepository, userRepository: env.userRepository, communityRepository: env.communityRepository))
    }

    var body: some View {
        Form {
            Section("Profil") {
                Text("Pseudo : \(vm.me?.pseudo ?? "")")
                Text("XP total : \(vm.me?.xpTotal ?? 0)")
                Button("Modifier le profil", action: onEditProfile)
                Button("Déconnexion") {
                    vm.signOut(onDone: onSignOut)
                }
            }
        }
        .navigationTitle("Profil")
        .onAppear { vm.start() }
    }
}
