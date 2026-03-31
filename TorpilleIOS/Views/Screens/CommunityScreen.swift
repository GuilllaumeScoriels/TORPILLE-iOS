import SwiftUI
import AVFoundation

struct CommunityScreen: View {
    @StateObject private var vm: CommunityViewModel
    let communityId: String
    let onBack: () -> Void
    let onOpenInfo: () -> Void

    @StateObject private var audioRecorder = AudioRecorderService()

    @State private var text = ""
    @State private var selectedFileURL: URL?
    @State private var selectedMemberID = ""
    @State private var selectedResponseMemberID = ""
    @State private var torpilleFileURL: URL?
    @State private var responseFileURL: URL?
    @State private var torpilleCapturePurpose: TorpilleCapturePurpose = .newTorpille

    @State private var playbackURL: URL?
    @State private var playbackMediaType: MediaPlaybackType = .video
    @State private var playbackTitle: String?
    @State private var playbackTagX: Double?
    @State private var playbackTagY: Double?
    @State private var isLoadingMedia = false

    @State private var audioPlayer: AVPlayer?
    @State private var playingAudioMessageId: String?

    @State private var showCommunityCamera = false
    @State private var showTorpilleCamera = false
    @State private var showUnseenTorpilles = false

    init(env: AppEnvironment, communityId: String, onBack: @escaping () -> Void, onOpenInfo: @escaping () -> Void) {
        self.communityId = communityId
        self.onBack = onBack
        self.onOpenInfo = onOpenInfo
        _vm = StateObject(wrappedValue: CommunityViewModel(communityRepo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            topTorpilleBar

            if let pendingFrom = vm.myMember?.pendingFromPseudo, vm.myMember?.pendingTorpilleId != nil {
                pendingResponseBanner(from: pendingFrom)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let error = vm.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            List {
                ForEach(vm.messages, id: \.stableId) { message in
                    messageRow(message)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)

            bottomComposer
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .onAppear { vm.start(communityId: communityId) }
        .onDisappear {
            audioPlayer?.pause()
            audioPlayer = nil
            audioRecorder.clear()
        }
        .sheet(isPresented: $showCommunityCamera) {
            CameraMediaPicker(selectedFileURL: $selectedFileURL, allowedTypes: .photoAndVideo)
        }
        .sheet(isPresented: $showTorpilleCamera) {
            CameraMediaPicker(selectedFileURL: $torpilleFileURL, allowedTypes: .videoOnly)
        }
        .sheet(isPresented: $showUnseenTorpilles, onDismiss: {
            vm.markTorpillesSeen(communityId: communityId)
        }) {
            UnseenTorpillesSheet(vm: vm, playback: playTorpille)
        }
        .sheet(item: Binding(get: {
            playbackURL.map { PlaybackContainer(url: $0, mediaType: playbackMediaType, title: playbackTitle, tagX: playbackTagX, tagY: playbackTagY) }
        }, set: { newValue in
            playbackURL = newValue?.url
            playbackMediaType = newValue?.mediaType ?? .video
            playbackTitle = newValue?.title
            playbackTagX = newValue?.tagX
            playbackTagY = newValue?.tagY
        })) { item in
            VideoPlayerSheet(url: item.url, mediaType: item.mediaType, overlayText: item.title, tagX: item.tagX, tagY: item.tagY)
        }
        .confirmationDialog("Choisir un membre", isPresented: Binding(get: { torpilleFileURL != nil && torpilleCapturePurpose == .newTorpille }, set: { if !$0 { torpilleFileURL = nil } })) {
            ForEach(candidateMembers, id: \.uid) { member in
                Button("Envoyer à @\(member.displayName)") {
                    if let torpilleFileURL {
                        vm.sendVideoTorpille(communityId: communityId, fileURL: torpilleFileURL, taggedMember: member, tagX: 0.5, tagY: 0.2)
                        self.torpilleFileURL = nil
                    }
                }
            }
            Button("Annuler", role: .cancel) {
                torpilleFileURL = nil
            }
        }
        .onChange(of: selectedFileURL) { _, newValue in
            guard let newValue else { return }
            vm.sendCapturedMedia(communityId: communityId, fileURL: newValue)
            selectedFileURL = nil
        }
        .onChange(of: torpilleFileURL) { _, newValue in
            guard let newValue else { return }
            if torpilleCapturePurpose == .response {
                responseFileURL = newValue
                torpilleFileURL = nil
            }
        }
        .overlay {
            if isLoadingMedia || vm.isSending {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView(isLoadingMedia ? "Chargement du média…" : "Envoi…")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            Spacer()
            Text("Communauté")
                .font(.headline)
            Spacer()
            Button(action: onOpenInfo) {
                Image(systemName: "info.circle")
                    .font(.headline)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var topTorpilleBar: some View {
        HStack(spacing: 12) {
            Button {
                showUnseenTorpilles = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: vm.unseenTorpilles.isEmpty ? "bolt" : "bolt.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Torpilles non vues")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(vm.unseenTorpilles.isEmpty ? "Aucune nouvelle torpille" : "\(vm.unseenTorpilles.count) à regarder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !vm.unseenTorpilles.isEmpty {
                        Text("\(vm.unseenTorpilles.count)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)

            Button {
                torpilleCapturePurpose = .newTorpille
                showTorpilleCamera = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 28))
                    Text("Torpille")
                        .font(.caption2.weight(.semibold))
                }
                .frame(width: 82, height: 82)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func pendingResponseBanner(from pendingFrom: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Torpille en attente")
                .font(.subheadline.weight(.semibold))
            Text("Tu dois répondre à la torpille de @\(pendingFrom).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let responseFileURL {
                Text("Vidéo prête : \(responseFileURL.lastPathComponent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Filmer la réponse") {
                    torpilleCapturePurpose = .response
                    showTorpilleCamera = true
                }
                .buttonStyle(.borderedProminent)

                Menu("Relancer vers") {
                    ForEach(candidateMembers, id: \.uid) { member in
                        Button("@\(member.displayName)") {
                            guard let responseFileURL, vm.myMember?.pendingTorpilleId != nil else { return }
                            vm.respond(communityId: communityId, fileURL: responseFileURL, nextTaggedMember: member, tagX: 0.5, tagY: 0.2)
                            self.responseFileURL = nil
                        }
                    }
                }
                .disabled(responseFileURL == nil || vm.myMember?.pendingTorpilleId == nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func messageRow(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(message.senderPseudo)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let createdAt = message.createdAt?.formattedDateTime {
                    Text(createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if message.type == "video" {
                VideoMessageRow(message: message) {
                    Task { await playVideo(message: message) }
                }
            } else if message.type == "audio" {
                AudioMessageRow(message: message, isPlaying: playingAudioMessageId == message.stableId) {
                    Task { await playAudio(message: message) }
                }
            } else if message.type == "image" {
                ImageMessageRow(message: message) {
                    Task { await openImage(message: message) }
                }
            } else {
                Text(message.text ?? "")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var bottomComposer: some View {
        HStack(spacing: 12) {
            Button {
                showCommunityCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                TextField("Écrire un message…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    vm.sendText(communityId: communityId, text: trimmed)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())

            Button {
                handleVoiceButton()
            } label: {
                Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.title3)
                    .foregroundStyle(audioRecorder.isRecording ? .red : .primary)
                    .frame(width: 48, height: 48)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var candidateMembers: [Member] {
        let myUID = vm.me?.uid
        return vm.members.filter { $0.uid != myUID }
    }

    private func handleVoiceButton() {
        Task {
            do {
                if audioRecorder.isRecording {
                    let fileURL = try audioRecorder.stopRecording()
                    vm.sendAudioMessage(communityId: communityId, fileURL: fileURL, durationSeconds: audioRecorder.recordedDurationSeconds)
                    audioRecorder.clear()
                } else {
                    try await audioRecorder.startRecording()
                }
            } catch {
                vm.error = error.localizedDescription
            }
        }
    }

    @MainActor
    private func playVideo(message: Message) async {
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
    private func playTorpille(_ torpille: Torpille) async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let url = try await vm.resolvePlaybackURL(for: torpille)
            playbackURL = url
            playbackMediaType = .video
            playbackTitle = torpille.taggedPseudo
            playbackTagX = torpille.tagX
            playbackTagY = torpille.tagY
        } catch {
            vm.error = error.localizedDescription
        }
    }

    @MainActor
    private func openImage(message: Message) async {
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
    private func playAudio(message: Message) async {
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

enum TorpilleCapturePurpose: Equatable {
    case newTorpille
    case response
}

enum MediaPlaybackType: Equatable {
    case video
    case image
}

struct PlaybackContainer: Identifiable {
    let id = UUID()
    let url: URL
    let mediaType: MediaPlaybackType
    let title: String?
    let tagX: Double?
    let tagY: Double?
}

private struct UnseenTorpillesSheet: View {
    @ObservedObject var vm: CommunityViewModel
    let playback: (Torpille) async -> Void

    var body: some View {
        NavigationStack {
            List {
                if vm.unseenTorpilles.isEmpty {
                    ContentUnavailableView("Aucune torpille non vue", systemImage: "bolt.slash")
                } else {
                    ForEach(vm.unseenTorpilles, id: \.stableId) { torpille in
                        Button {
                            Task { await playback(torpille) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(torpille.taggedPseudo.map { "Torpille → @\($0)" } ?? "Torpille")
                                    .foregroundStyle(.primary)
                                if let createdAt = torpille.createdAt?.formattedDateTime {
                                    Text(createdAt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Torpilles")
        }
    }
}
