/**
 Fichier : CommunityScreen.swift
 Rôle :
 - Écran principal d'une communauté : messages, torpilles vidéo et réponses.

 Ce que fait ce fichier :
 - Affiche les messages texte et vidéo.
 - Fournit des boutons vidéo fonctionnels qui ouvrent un lecteur intégré.
 - Permet d'envoyer une torpille vidéo ou de répondre à une torpille en attente.
 - Utilise `VideoPicker` pour sélectionner un fichier vidéo avant envoi.

 Pourquoi c'est utile :
 - C'est l'écran le plus proche du flux Android amélioré fourni par l'utilisateur.
 */

import SwiftUI

private enum CommunityComposerMode: String, CaseIterable, Identifiable {
    case text = "Texte"
    case video = "Torpille vidéo"
    case response = "Réponse vidéo"

    var id: String { rawValue }
}

struct CommunityScreen: View {
    @StateObject private var vm: CommunityViewModel
    let communityId: String
    let onBack: () -> Void
    let onOpenInfo: () -> Void

    @State private var text = ""
    @State private var selectedFileURL: URL?
    @State private var selectedMemberID = ""
    @State private var selectedResponseMemberID = ""
    @State private var mode: CommunityComposerMode = .text

    @State private var playbackURL: URL?
    @State private var playbackTitle: String?
    @State private var playbackTagX: Double?
    @State private var playbackTagY: Double?
    @State private var isLoadingVideo = false

    init(env: AppEnvironment, communityId: String, onBack: @escaping () -> Void, onOpenInfo: @escaping () -> Void) {
        self.communityId = communityId
        self.onBack = onBack
        self.onOpenInfo = onOpenInfo
        _vm = StateObject(wrappedValue: CommunityViewModel(communityRepo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Retour", action: onBack)
                Spacer()
                Text("Communauté")
                    .font(.headline)
                Spacer()
                Button("Infos", action: onOpenInfo)
            }
            .padding(.horizontal)

            Picker("Mode", selection: $mode) {
                ForEach(CommunityComposerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            composerSection
                .padding(.horizontal)

            if let pendingFrom = vm.myMember?.pendingFromPseudo,
               vm.myMember?.pendingTorpilleId != nil {
                Text("Tu as une torpille en attente de @\(pendingFrom).")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            if let error = vm.error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            List {
                ForEach(vm.messages, id: \.stableId) { message in
                    if message.type == "video" {
                        VideoMessageRow(message: message) {
                            Task {
                                await play(message: message)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.senderPseudo).font(.headline)
                            Text(message.text ?? "")
                            if let createdAt = message.createdAt?.formattedDateTime {
                                Text(createdAt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { vm.start(communityId: communityId) }
        .sheet(item: Binding(get: {
            playbackURL.map { PlaybackContainer(url: $0, title: playbackTitle, tagX: playbackTagX, tagY: playbackTagY) }
        }, set: { newValue in
            playbackURL = newValue?.url
            playbackTitle = newValue?.title
            playbackTagX = newValue?.tagX
            playbackTagY = newValue?.tagY
        })) { item in
            VideoPlayerSheet(url: item.url, overlayText: item.title, tagX: item.tagX, tagY: item.tagY)
        }
        .overlay {
            if isLoadingVideo || vm.isSending {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView(isLoadingVideo ? "Chargement de la vidéo…" : "Envoi…")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    @ViewBuilder
    private var composerSection: some View {
        switch mode {
        case .text:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Envoyer") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    vm.sendText(communityId: communityId, text: trimmed)
                    text = ""
                }
            }
        case .video:
            VStack(alignment: .leading, spacing: 8) {
                VideoPicker(selectedFileURL: $selectedFileURL)
                Picker("Cible", selection: $selectedMemberID) {
                    Text("Choisir un membre").tag("")
                    ForEach(candidateMembers, id: \.uid) { member in
                        Text(member.displayName).tag(member.uid)
                    }
                }
                .pickerStyle(.menu)

                Button("Envoyer la torpille vidéo") {
                    guard let fileURL = selectedFileURL,
                          let member = candidateMembers.first(where: { $0.uid == selectedMemberID }) else { return }
                    vm.sendVideoTorpille(communityId: communityId, fileURL: fileURL, taggedMember: member, tagX: 0.5, tagY: 0.2)
                    selectedFileURL = nil
                    selectedMemberID = ""
                }
                .disabled(selectedFileURL == nil || selectedMemberID.isEmpty)
            }
        case .response:
            VStack(alignment: .leading, spacing: 8) {
                VideoPicker(selectedFileURL: $selectedFileURL)
                Picker("Relancer vers", selection: $selectedResponseMemberID) {
                    Text("Choisir un membre").tag("")
                    ForEach(candidateMembers, id: \.uid) { member in
                        Text(member.displayName).tag(member.uid)
                    }
                }
                .pickerStyle(.menu)

                Button("Répondre et relancer") {
                    guard let fileURL = selectedFileURL,
                          let member = candidateMembers.first(where: { $0.uid == selectedResponseMemberID }) else { return }
                    vm.respond(communityId: communityId, fileURL: fileURL, nextTaggedMember: member, tagX: 0.5, tagY: 0.2)
                    selectedFileURL = nil
                    selectedResponseMemberID = ""
                }
                .disabled(vm.myMember?.pendingTorpilleId == nil || selectedFileURL == nil || selectedResponseMemberID.isEmpty)
            }
        }
    }

    private var candidateMembers: [Member] {
        let myUID = vm.me?.uid
        return vm.members.filter { $0.uid != myUID }
    }

    @MainActor
    private func play(message: Message) async {
        isLoadingVideo = true
        defer { isLoadingVideo = false }
        do {
            let url = try await vm.resolvePlaybackURL(for: message)
            playbackURL = url
            playbackTitle = message.taggedPseudo
            playbackTagX = message.tagX
            playbackTagY = message.tagY
        } catch {
            vm.error = error.localizedDescription
        }
    }
}

private struct PlaybackContainer: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
    let tagX: Double?
    let tagY: Double?
}
