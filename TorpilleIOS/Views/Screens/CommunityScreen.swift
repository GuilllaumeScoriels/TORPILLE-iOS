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
    @State private var showTorpilleRecipientSheet = false
    @State private var torpilleRecipientQuery = ""
    @State private var hasScrolledToBottomOnOpen = false
    @FocusState private var isComposerFocused: Bool

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

            /*if let error = vm.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }*/

            ScrollViewReader { proxy in
                List {
                    ForEach(vm.messages, id: \.stableId) { message in
                        messageRow(message)
                            .id(message.stableId)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: vm.messages.count) { oldCount, newCount in
                    let isFirstLoad = !hasScrolledToBottomOnOpen
                    let didReceiveNewMessage = newCount > oldCount
                    guard isFirstLoad || didReceiveNewMessage else { return }
                    scrollToBottom(using: proxy, animated: !isFirstLoad)
                }
            }

            bottomComposer
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .navigationBarBackButtonHidden(true)
        .simultaneousGesture(hideKeyboardGesture)
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
        .sheet(isPresented: $showTorpilleRecipientSheet, onDismiss: {
            if torpilleCapturePurpose == .newTorpille, vm.isSending == false, torpilleFileURL != nil {
                torpilleFileURL = nil
            }
        }) {
            TorpilleRecipientSheet(
                searchText: $torpilleRecipientQuery,
                members: candidateMembers,
                onCancel: {
                    torpilleFileURL = nil
                    torpilleRecipientQuery = ""
                    showTorpilleRecipientSheet = false
                },
                onSelectMember: { member in
                    guard let torpilleFileURL else { return }
                    vm.sendVideoTorpille(
                        communityId: communityId,
                        fileURL: torpilleFileURL,
                        taggedMember: member,
                        fallbackPseudoText: member.displayName,
                        tagX: 0.5,
                        tagY: 0.2
                    )
                    self.torpilleFileURL = nil
                    torpilleRecipientQuery = ""
                    showTorpilleRecipientSheet = false
                },
                onUseTypedText: { typedText in
                    guard let torpilleFileURL else { return }
                    vm.sendVideoTorpille(
                        communityId: communityId,
                        fileURL: torpilleFileURL,
                        taggedMember: exactMatch(for: typedText),
                        fallbackPseudoText: typedText,
                        tagX: 0.5,
                        tagY: 0.2
                    )
                    self.torpilleFileURL = nil
                    torpilleRecipientQuery = ""
                    showTorpilleRecipientSheet = false
                }
            )
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
            } else {
                torpilleRecipientQuery = ""
                showTorpilleRecipientSheet = true
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

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        guard let lastMessageId = vm.messages.last?.stableId else { return }

        let action = {
            proxy.scrollTo(lastMessageId, anchor: .bottom)
            hasScrolledToBottomOnOpen = true
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation {
                    action()
                }
            } else {
                action()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(ActionAccent.slate.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
            Text("Communauté")
                .font(.headline)
            Spacer()

            Button(action: onOpenInfo) {
                Image(systemName: "info.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(ActionAccent.ocean.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
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
                            .foregroundStyle(.white)
                        Text(vm.unseenTorpilles.isEmpty ? "Aucune nouvelle torpille" : "\(vm.unseenTorpilles.count) à regarder")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    Spacer()
                    if !vm.unseenTorpilles.isEmpty {
                        Text("\(vm.unseenTorpilles.count)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.18))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(16)
                .background(ActionAccent.violet.gradient)
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
                .background(ActionAccent.coral.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func exactMatch(for text: String) -> Member? {
        let normalizedQuery = text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else { return nil }
        return candidateMembers.first { member in
            member.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedQuery
        }
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
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(ActionAccent.coral.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
        .background(ActionAccent.gold.tint.opacity(0.16))
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
                    .background(ActionAccent.ocean.gradient)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                TextField("Écrire un message…", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    vm.sendText(communityId: communityId, text: trimmed)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ActionAccent.sunset.tint)
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
                    .frame(width: 48, height: 48)
                    .background((audioRecorder.isRecording ? ActionAccent.coral : ActionAccent.meadow).gradient)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }


    private var hideKeyboardGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard isComposerFocused else { return }
                let verticalMovement = value.translation.height
                let horizontalMovement = abs(value.translation.width)
                guard verticalMovement > 40, verticalMovement > horizontalMovement else { return }
                isComposerFocused = false
            }
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

private struct TorpilleRecipientSheet: View {
    @Binding var searchText: String
    let members: [Member]
    let onCancel: () -> Void
    let onSelectMember: (Member) -> Void
    let onUseTypedText: (String) -> Void

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredMembers: [Member] {
        guard !trimmedSearchText.isEmpty else { return members }
        let normalizedQuery = trimmedSearchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return members.filter { member in
            member.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedQuery)
        }
    }

    private var hasExactMatch: Bool {
        let normalizedQuery = trimmedSearchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else { return false }
        return members.contains { member in
            member.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedQuery
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Qui veux-tu torpiller ?")
                    .font(.title3.weight(.semibold))

                Text("Tape un pseudo exact pour identifier un membre et lui envoyer la notification. Sinon, le texte saisi sera seulement affiché sur la torpille.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Pseudo à torpiller", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !trimmedSearchText.isEmpty, !hasExactMatch {
                            Button {
                                onUseTypedText(trimmedSearchText)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Utiliser « \(trimmedSearchText) »")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Aucun membre ne sera identifié, mais ce texte apparaîtra sur la vidéo.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(ActionAccent.gold.tint.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(filteredMembers, id: \.uid) { member in
                            Button {
                                onSelectMember(member)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("@\(member.displayName)")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("Identifie ce membre et envoie-lui la notification.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Choisir la cible")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
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
