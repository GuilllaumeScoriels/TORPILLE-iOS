/**
 Fichier : CommunityManagementScreens.swift
 Rôle :
 - Regroupe les écrans de création, de jonction et d'information d'une communauté.

 Ce que fait ce fichier :
 - Permet de créer une communauté, rejoindre une invitation et modifier les
   paramètres administrables de base.
 - Affiche la liste des membres avec leur état courant.
 */

import SwiftUI

struct CreateCommunityScreen: View {
    @StateObject private var vm: CreateCommunityViewModel
    let onCreated: (String) -> Void
    let onBack: () -> Void

    init(env: AppEnvironment, onCreated: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        self.onCreated = onCreated
        self.onBack = onBack
        _vm = StateObject(wrappedValue: CreateCommunityViewModel(repo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: "Nouvelle communauté",
                    subtitle: "Crée un espace accueillant, règle son tempo et invite tes joueurs.",
                    primarySymbol: "person.3.fill",
                    secondarySymbol: "flag.checkered.2.crossed",
                    cornerSymbol: "plus.circle.fill",
                    accent: .sunset
                )

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Nom", text: $vm.name)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    TextField("Temps de réponse (secondes)", text: $vm.responseTime)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Toggle("Communauté publique", isOn: $vm.isPublic)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Button {
                    vm.create(onCreated: onCreated)
                } label: {
                    IllustratedActionButton(
                        title: vm.isLoading ? "Création…" : "Créer",
                        subtitle: "Valide les paramètres et ouvre la communauté.",
                        systemImage: "plus.circle.fill",
                        illustrationSymbol: "person.3.sequence.fill",
                        accent: .meadow
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading || vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: onBack) {
                    CompactActionButton(title: "Retour", systemImage: "arrow.left.circle.fill", accent: .slate)
                }
                .buttonStyle(.plain)

                if let error = vm.error {
                    Text(error)
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
        .navigationTitle("Créer")
    }
}

struct JoinCommunityScreen: View {
    @StateObject private var vm: JoinCommunityViewModel
    let communityId: String
    let onJoined: () -> Void
    let onCancel: () -> Void

    init(env: AppEnvironment, communityId: String, onJoined: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.communityId = communityId
        self.onJoined = onJoined
        self.onCancel = onCancel
        _vm = StateObject(wrappedValue: JoinCommunityViewModel(repo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        VStack(spacing: 18) {
            WelcomeHeroCard(
                title: "Invitation communauté",
                subtitle: "Patiente un instant pendant que Torpille vérifie ton invitation.",
                primarySymbol: "envelope.open.fill",
                secondarySymbol: "person.2.badge.plus",
                cornerSymbol: "checkmark.circle.fill",
                accent: .ocean
            )

            if vm.loading { ProgressView() }

            if let error = vm.error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button(action: onCancel) {
                CompactActionButton(title: "Retour", systemImage: "arrow.left.circle.fill", accent: .coral)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .task {
            await vm.join(communityId, onJoined: onJoined)
        }
    }
}

struct CommunityInfoScreen: View {
    @StateObject private var vm: CommunityInfoViewModel
    let communityId: String
    let onBack: () -> Void

    init(env: AppEnvironment, communityId: String, onBack: @escaping () -> Void) {
        self.communityId = communityId
        self.onBack = onBack
        _vm = StateObject(wrappedValue: CommunityInfoViewModel(repo: env.communityRepository))
    }

    var body: some View {
        List {
            Section {
                Button(action: onBack) {
                    CompactActionButton(title: "Retour", systemImage: "arrow.left.circle.fill", accent: .slate)
                }
                .buttonStyle(.plain)

                Text(vm.community?.name ?? "Communauté")
                    .font(.title2.weight(.bold))

                if let community = vm.community {
                    Text("Invitation : https://torpille-38783.web.app/join?cid=\(community.stableId)")
                        .font(.footnote)
                        .textSelection(.enabled)
                    Text("La page d’invitation propose maintenant deux boutons de téléchargement : Android et iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if vm.community != nil {
                Section("Paramètres") {
                    Toggle("Communauté publique", isOn: $vm.isPublic)
                    TextField("Temps de réponse", text: $vm.responseTime)
                        .keyboardType(.numberPad)
                    Button {
                        vm.saveSettings(communityId: communityId)
                    } label: {
                        CompactActionButton(title: "Enregistrer", systemImage: "square.and.arrow.down.fill", accent: .meadow)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Participants") {
                ForEach(vm.members) { member in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.displayName).font(.headline)
                        Text("XP : \(member.xpInCommunity)")
                            .font(.subheadline)
                        Text(member.pendingTorpilleId == nil ? "OK" : "Torpillé en attente")
                            .font(.caption)
                            .foregroundStyle(member.pendingTorpilleId == nil ? .green : .orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = vm.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Infos communauté")
        .onAppear { vm.start(communityId: communityId) }
    }
}
