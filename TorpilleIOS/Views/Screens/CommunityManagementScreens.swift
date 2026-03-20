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
        Form {
            Section("Nouvelle communauté") {
                TextField("Nom", text: $vm.name)
                TextField("Temps de réponse (secondes)", text: $vm.responseTime)
                    .keyboardType(.numberPad)
                Toggle("Communauté publique", isOn: $vm.isPublic)
                Button(vm.isLoading ? "Création…" : "Créer") {
                    vm.create(onCreated: onCreated)
                }
                .disabled(vm.isLoading || vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Retour", action: onBack)
            }

            if let error = vm.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
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
        VStack(spacing: 16) {
            Text("Invitation communauté")
                .font(.title2)
            if vm.loading { ProgressView() }
            if let error = vm.error {
                Text(error).foregroundStyle(.red)
            }
            Button("Retour", action: onCancel)
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
                Button("Retour", action: onBack)
                Text(vm.community?.name ?? "Communauté")
                    .font(.title2)
                if let community = vm.community {
                    Text("Invitation : https://torpille-38783.web.app/join?cid=\(community.stableId)")
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            if vm.community != nil {
                Section("Paramètres") {
                    Toggle("Communauté publique", isOn: $vm.isPublic)
                    TextField("Temps de réponse", text: $vm.responseTime)
                        .keyboardType(.numberPad)
                    Button("Enregistrer") {
                        vm.saveSettings(communityId: communityId)
                    }
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
