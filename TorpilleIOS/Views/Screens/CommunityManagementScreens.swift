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
import AVFoundation
import AVKit

private struct ResponseTimePickerCard: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temps de réponse")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Picker("Heures", selection: $hours) {
                    ForEach(0..<24, id: \.self) { value in
                        Text(value == 1 ? "1 heure" : "\(value) heures").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Minutes", selection: $minutes) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(value == 1 ? "1 minute" : "\(value) minutes").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Délai actuel : \(formatResponseTime(Int64(hours * 3600 + minutes * 60)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

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

                    ResponseTimePickerCard(hours: $vm.responseHours, minutes: $vm.responseMinutes)

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
    private let env: AppEnvironment
    let communityId: String
    let onBack: () -> Void

    init(env: AppEnvironment, communityId: String, onBack: @escaping () -> Void) {
        self.env = env
        self.communityId = communityId
        self.onBack = onBack
        _vm = StateObject(wrappedValue: CommunityInfoViewModel(repo: env.communityRepository))
    }

    var body: some View {
        List {
            Section {
                Button(action: onBack) {
                    CompactActionButton(title: "Retour à la discussion", systemImage: "arrow.left.circle.fill", accent: .slate)
                }
                .buttonStyle(.plain)

                Text(vm.community?.name ?? "Communauté")
                    .font(.title2.weight(.bold))

                if let community = vm.community {
                    Text("Invitation : https://torpille-38783.web.app/join?cid=\(community.stableId)")
                        .font(.footnote)
                        .textSelection(.enabled)
                    Text("La page d’invitation permet de rejoindre cette communauté.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SavedCommunityMessagesScreen(env: env, communityId: communityId)
                    } label: {
                        HStack {
                            CompactActionButton(
                                title: "Contenus enregistres",
                                systemImage: "bookmark.fill",
                                accent: .gold
                            )
                            Spacer()
                            Text("\(vm.savedMessageCount)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if let infoMessage = vm.infoMessage {
                Section {
                    Text(infoMessage)
                        .foregroundStyle(.green)
                }
            }

            if vm.community != nil {
                Section("Paramètres") {
                    Toggle("Communauté publique", isOn: $vm.isPublic)
                    ResponseTimePickerCard(hours: $vm.responseHours, minutes: $vm.responseMinutes)
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
                        HStack(spacing: 8) {
                            Text(member.displayName)
                                .font(.headline)

                            if member.uid == vm.community?.adminUid {
                                Text("Admin")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ActionAccent.ocean.tint)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ActionAccent.ocean.tint.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Spacer(minLength: 0)
                        }
                        Text("XP : \(member.xpInCommunity)")
                            .font(.subheadline)
                        Text(member.pendingTorpilleId == nil ? "OK" : "Torpillé en attente")
                            .font(.caption)
                            .foregroundStyle(member.pendingTorpilleId == nil ? .green : .orange)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        if vm.canModerateMembers, member.uid != vm.community?.adminUid {
                            Button(role: .destructive) {
                                vm.removeMember(communityId: communityId, member: member)
                            } label: {
                                Label("Retirer de la communauté", systemImage: "person.crop.circle.badge.minus")
                            }

                            Button(role: .destructive) {
                                vm.banMember(communityId: communityId, member: member)
                            } label: {
                                Label("Bannir", systemImage: "hand.raised.fill")
                            }
                        }
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

struct SavedCommunityMessagesScreen: View {
    @StateObject private var vm: SavedCommunityMessagesViewModel
    let communityId: String

    @State private var selectedStoryIndex = 0
    @State private var showStoriesViewer = false
    @State private var playbackURL: URL?
    @State private var playbackMediaType: MediaPlaybackType = .video
    @State private var playbackTitle: String?
    @State private var playbackTagX: Double?
    @State private var playbackTagY: Double?
    @State private var isLoadingMedia = false
    @State private var audioPlayer: AVPlayer?
    @State private var playingAudioMessageId: String?

    init(env: AppEnvironment, communityId: String) {
        self.communityId = communityId
        _vm = StateObject(wrappedValue: SavedCommunityMessagesViewModel(repo: env.communityRepository))
    }

    var body: some View {
        List {
            if vm.messages.isEmpty {
                ContentUnavailableView(
                    "Aucun contenu enregistre",
                    systemImage: "bookmark.slash",
                    description: Text("Maintiens un contenu appuye dans la discussion pour l'enregistrer ici.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(vm.messages.enumerated()), id: \.element.stableId) { index, message in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            selectedStoryIndex = index
                            showStoriesViewer = true
                        } label: {
                            savedMessageRow(message)
                        }
                        .buttonStyle(.plain)

                        if vm.canPublishToMemories(message) {
                            if vm.isPublishedInMemories(message) {
                                Button(role: .destructive) {
                                    vm.removeFromMemories(communityId: communityId, message: message)
                                } label: {
                                    Label("Retirer des Memories", systemImage: "trash")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    vm.publishToMemories(communityId: communityId, message: message)
                                } label: {
                                    Label("Publier en Memories", systemImage: "play.rectangle.fill")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(ActionAccent.coral.tint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if let infoMessage = vm.infoMessage {
                Section {
                    Text(infoMessage)
                        .foregroundStyle(.green)
                }
            }

            if let error = vm.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Contenus enregistres")
        .onAppear { vm.start(communityId: communityId) }
        .fullScreenCover(isPresented: $showStoriesViewer) {
            SavedMessagesStoriesViewer(
                vm: vm,
                communityId: communityId,
                messages: vm.messages,
                initialIndex: selectedStoryIndex
            )
        }
        .sheet(item: Binding(get: {
            playbackURL.map { PlaybackContainer(url: $0, mediaType: playbackMediaType, title: playbackTitle, sender: nil, tagX: playbackTagX, tagY: playbackTagY) }
        }, set: { newValue in
            playbackURL = newValue?.url
            playbackMediaType = newValue?.mediaType ?? .video
            playbackTitle = newValue?.title
            playbackTagX = newValue?.tagX
            playbackTagY = newValue?.tagY
        })) { item in
            VideoPlayerSheet(url: item.url, mediaType: item.mediaType, overlayText: item.title, tagX: item.tagX, tagY: item.tagY)
        }
        .overlay {
            if isLoadingMedia {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Chargement du media…")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onDisappear {
            audioPlayer?.pause()
            audioPlayer = nil
        }
    }

    private func savedMessageRow(_ message: Message) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: message))
                .font(.headline)
                .foregroundStyle(ActionAccent.ocean.tint)
                .frame(width: 36, height: 36)
                .background(ActionAccent.ocean.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("@\(message.senderPseudo)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(messageSummary(for: message))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let savedAt = message.savedAt?.dateValue() {
                    Text("Enregistre le \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func iconName(for message: Message) -> String {
        switch message.type {
        case "image":
            return "photo.fill"
        case "video":
            return "video.fill"
        case "audio":
            return "waveform"
        default:
            return "text.bubble.fill"
        }
    }

    private func messageSummary(for message: Message) -> String {
        switch message.type {
        case "text":
            return message.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message.text! : "Message texte"
        case "image":
            return "Image"
        case "video":
            if let taggedPseudo = message.taggedPseudo, !taggedPseudo.isEmpty {
                return "Video pour @\(taggedPseudo)"
            }
            return "Video"
        case "audio":
            return "Message vocal"
        default:
            return "Contenu"
        }
    }

    private func open(_ message: Message) {
        switch message.type {
        case "audio":
            Task { await playAudio(message) }
        case "image":
            Task { await openImage(message) }
        case "video":
            Task { await playVideo(message) }
        default:
            break
        }
    }

    @MainActor
    private func playVideo(_ message: Message) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let url = try await vm.resolvePlaybackURL(for: message)
            playbackURL = url
            playbackMediaType = .video
            playbackTitle = message.taggedPseudo
            playbackTagX = message.tagX
            playbackTagY = message.tagY
        } catch {
            vm.error = error.localizedDescription
        }
    }

    @MainActor
    private func openImage(_ message: Message) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let url = try await vm.resolvePlaybackURL(for: message)
            playbackURL = url
            playbackMediaType = .image
            playbackTitle = nil
            playbackTagX = nil
            playbackTagY = nil
        } catch {
            vm.error = error.localizedDescription
        }
    }

    @MainActor
    private func playAudio(_ message: Message) async {
        if playingAudioMessageId == message.stableId {
            audioPlayer?.pause()
            audioPlayer = nil
            playingAudioMessageId = nil
            return
        }

        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let url = try await vm.resolvePlaybackURL(for: message)
            let player = AVPlayer(url: url)
            audioPlayer?.pause()
            audioPlayer = player
            playingAudioMessageId = message.stableId
            player.play()
        } catch {
            vm.error = error.localizedDescription
        }
    }
}

private struct SavedMessagesStoriesViewer: View {
    @ObservedObject var vm: SavedCommunityMessagesViewModel
    let communityId: String
    let messages: [Message]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if messages.isEmpty {
                ContentUnavailableView("Aucun contenu enregistre", systemImage: "bookmark.slash")
                    .foregroundStyle(.white)
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(messages.enumerated()), id: \.element.stableId) { index, message in
                        SavedStoryPage(message: message, vm: vm)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    HStack(spacing: 4) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, _ in
                            Capsule()
                                .fill(index <= selection ? Color.white : Color.white.opacity(0.28))
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal, 16)

                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("@\(messages[selection].senderPseudo)")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)

                            Text(storySummary(for: messages[selection]))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.9))

                            if let savedAt = messages[selection].savedAt?.dateValue() {
                                Text(savedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }

                        Spacer()

                        if vm.canPublishToMemories(messages[selection]) {
                            if vm.isPublishedInMemories(messages[selection]) {
                                Button {
                                    vm.removeFromMemories(communityId: communityId, message: messages[selection])
                                } label: {
                                    Label("Retirer", systemImage: "trash")
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.red.opacity(0.9))
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    vm.publishToMemories(communityId: communityId, message: messages[selection])
                                } label: {
                                    Label("Publier", systemImage: "sparkles.tv.fill")
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(ActionAccent.coral.gradient)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                    .background(.black.opacity(0.32))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }

                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard selection > 0 else { return }
                            selection -= 1
                        }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard selection < messages.count - 1 else { return }
                            selection += 1
                        }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            selection = min(max(initialIndex, 0), max(messages.count - 1, 0))
        }
    }

    private func storySummary(for message: Message) -> String {
        switch message.type {
        case "text":
            return message.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message.text! : "Message texte"
        case "image":
            return "Photo enregistree"
        case "video":
            return message.torpilleId?.isEmpty == false ? "Torpille enregistree" : "Video enregistree"
        case "audio":
            return "Message vocal enregistre"
        default:
            return "Contenu enregistre"
        }
    }
}

private struct SavedStoryPage: View {
    let message: Message
    @ObservedObject var vm: SavedCommunityMessagesViewModel

    @State private var resolvedURL: URL?
    @State private var loadingError: String?
    @State private var isLoading = false
    @State private var player: AVPlayer?
    @State private var isAudioPlaying = false

    var body: some View {
        ZStack {
            switch message.type {
            case "video":
                videoContent
            case "image":
                imageContent
            case "audio":
                audioContent
            default:
                textContent
            }
        }
        .onAppear {
            Task { await prepareIfNeeded() }
        }
        .onDisappear {
            player?.pause()
            isAudioPlaying = false
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        if let resolvedURL {
            VideoPlayer(player: player ?? AVPlayer(url: resolvedURL))
                .onAppear {
                    let activePlayer = player ?? AVPlayer(url: resolvedURL)
                    player = activePlayer
                    activePlayer.play()
                }
                .onDisappear {
                    player?.pause()
                }
        } else if isLoading {
            ProgressView("Chargement…")
                .tint(.white)
        } else if let loadingError {
            Text(loadingError)
                .foregroundStyle(.white)
                .padding()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let resolvedURL {
            AsyncImage(url: resolvedURL) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } placeholder: {
                ProgressView("Chargement…")
                    .tint(.white)
            }
        } else if isLoading {
            ProgressView("Chargement…")
                .tint(.white)
        } else if let loadingError {
            Text(loadingError)
                .foregroundStyle(.white)
                .padding()
        }
    }

    private var audioContent: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.white)

            Text("Message vocal")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            if let loadingError {
                Text(loadingError)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            Button {
                toggleAudioPlayback()
            } label: {
                Label(isAudioPlaying ? "Pause" : "Ecouter", systemImage: isAudioPlaying ? "pause.fill" : "play.fill")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(ActionAccent.ocean.gradient)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.92))

            Text(message.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message.text! : "Message texte")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.24),
                    Color(red: 0.26, green: 0.31, blue: 0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @MainActor
    private func prepareIfNeeded() async {
        guard resolvedURL == nil, loadingError == nil else { return }
        guard message.type == "video" || message.type == "image" || message.type == "audio" else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            resolvedURL = try await vm.resolvePlaybackURL(for: message)
        } catch {
            loadingError = error.localizedDescription
        }
    }

    private func toggleAudioPlayback() {
        Task {
            if isAudioPlaying {
                player?.pause()
                isAudioPlaying = false
                return
            }

            do {
                if resolvedURL == nil {
                    resolvedURL = try await vm.resolvePlaybackURL(for: message)
                }
                guard let resolvedURL else { return }
                let activePlayer = player ?? AVPlayer(url: resolvedURL)
                player = activePlayer
                activePlayer.play()
                isAudioPlaying = true
            } catch {
                loadingError = error.localizedDescription
            }
        }
    }
}
