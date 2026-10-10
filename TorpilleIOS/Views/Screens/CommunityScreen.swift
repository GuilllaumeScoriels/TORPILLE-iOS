import SwiftUI
import FirebaseCore
import AVFoundation
import PhotosUI

struct CommunityScreen: View {
    private static let bottomAnchorId = "community-bottom-anchor"

    @StateObject private var vm: CommunityViewModel
    @ObservedObject private var languageService: AppLanguageService
    let communityId: String
    let onBack: () -> Void
    let onOpenInfo: () -> Void

    @StateObject private var audioRecorder = AudioRecorderService()

    @State private var text = ""
    @State private var selectedFileURL: URL?
    @State private var selectedLibraryMediaItems: [PhotosPickerItem] = []
    @State private var pendingCommunityVideoURL: URL?
    @State private var showCommunityVideoConfirmation = false
    @State private var communityVideoWasApproved = false
    @State private var communityVideoWasDiscarded = false
    @State private var torpilleFileURL: URL?
    @State private var responseFileURL: URL?
    @State private var torpilleCapturePurpose: TorpilleCapturePurpose = .newTorpille

    @State private var playbackURL: URL?
    @State private var playbackMediaType: MediaPlaybackType = .video
    @State private var playbackTitle: String?
    @State private var playbackSender: String?
    @State private var playbackTagX: Double?
    @State private var playbackTagY: Double?
    @State private var isLoadingMedia = false

    @State private var audioPlayer: AVPlayer?
    @State private var playingAudioMessageId: String?

    @State private var showCommunityCamera = false
    @State private var showCommunityVideoCamera = false
    @State private var showCommunityCameraChoice = false
    @State private var showCommunityLibrary = false
    @State private var isPreparingLibraryMedia = false
    @State private var showTorpilleCamera = false
    @State private var showTorpilleRecipientSheet = false
    @State private var torpilleRecipientQuery = ""
    @State private var unseenPlaybackItems: [Torpille] = []
    @State private var unseenPlaybackIndex: Int?
    @State private var unseenPlaybackLastSeenTimestamp: Timestamp?
    @State private var unseenPlaybackLoadTask: Task<Void, Never>?
    @State private var unseenPlaybackGeneration = 0
    @State private var hasScrolledToBottomOnOpen = false
    @State private var hasPerformedInitialUnreadPositioning = false
    @State private var hasCompletedInitialPositioning = false
    @State private var isAtBottom = true
    @State private var reportingMessage: Message?
    @State private var messagePendingSenderBlock: Message?
    @FocusState private var isComposerFocused: Bool

    init(env: AppEnvironment, communityId: String, onBack: @escaping () -> Void, onOpenInfo: @escaping () -> Void) {
        self.communityId = communityId
        self.onBack = onBack
        self.onOpenInfo = onOpenInfo
        _languageService = ObservedObject(wrappedValue: env.languageService)
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

            if let infoMessage = vm.infoMessage, !infoMessage.isEmpty {
                Text(languageService.localizedRuntimeMessage(infoMessage))
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let error = vm.error {
                Text(languageService.localizedRuntimeMessage(error))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    List {
                        retentionNotice
                        if vm.isLoadingMessages {
                            TorpilleLoadingView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                        }

                        ForEach(Array(vm.messages.enumerated()), id: \.element.stableId) { index, message in
                            VStack(spacing: 0) {
                                if shouldShowDayHeader(for: index) {
                                    dayHeader(for: message)
                                }

                                if shouldShowUnreadHeader(for: index) {
                                    unreadHeader
                                        .id(unreadHeaderId(for: message))
                                }

                                messageRow(message)
                                    .id(message.stableId)
                                    .onAppear {
                                        handleMessageAppear(index: index)
                                    }
                                    .onDisappear {
                                        handleMessageDisappear(index: index)
                                    }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorId)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        scrollOnOpen(using: proxy)
                    }
                    .onChange(of: vm.firstUnreadMessageId) { _, _ in
                        guard !hasPerformedInitialUnreadPositioning else { return }
                        scrollOnOpen(using: proxy)
                    }
                    .onChange(of: vm.messages.count) { oldCount, newCount in
                        handleMessagesCountChange(oldCount: oldCount, newCount: newCount, using: proxy)
                    }

                    if !isAtBottom, !vm.messages.isEmpty {
                        Button {
                            scrollToBottom(using: proxy, animated: true)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(ActionAccent.ocean.gradient)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 18)
                        .padding(.bottom, 14)
                    }
                }
            }

        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomComposer
        }
        .simultaneousGesture(hideKeyboardGesture)
        .onAppear {
            hasScrolledToBottomOnOpen = false
            hasPerformedInitialUnreadPositioning = false
            hasCompletedInitialPositioning = false
            isAtBottom = true
            vm.start(communityId: communityId)
        }
        .onDisappear {
            audioPlayer?.pause()
            audioPlayer = nil
            audioRecorder.discardRecording()
        }
        .sheet(isPresented: $showCommunityCamera, onDismiss: {
            if pendingCommunityVideoURL != nil,
               !communityVideoWasApproved,
               !communityVideoWasDiscarded {
                showCommunityVideoConfirmation = true
            }
        }) {
            CameraMediaPicker(selectedFileURL: $selectedFileURL, allowedTypes: .photoOnly)
        }
        .sheet(isPresented: $showCommunityVideoCamera, onDismiss: {
            if pendingCommunityVideoURL != nil,
               !communityVideoWasApproved,
               !communityVideoWasDiscarded {
                showCommunityVideoConfirmation = true
            }
        }) {
            CameraMediaPicker(selectedFileURL: $selectedFileURL, allowedTypes: .videoOnly)
        }
        .confirmationDialog(
            languageService.phrase("Choisir le type de capture"),
            isPresented: $showCommunityCameraChoice,
            titleVisibility: .visible
        ) {
            Button(languageService.phrase("Prendre une photo")) {
                showCommunityCamera = true
            }
            Button(languageService.phrase("Filmer une vidéo")) {
                showCommunityVideoCamera = true
            }
            Button(languageService.phrase("Annuler"), role: .cancel) {}
        }
        .alert(
            languageService.mediaSendConfirmationTitle,
            isPresented: $showCommunityVideoConfirmation
        ) {
            Button(languageService.phrase("Envoyer")) {
                approvePendingCommunityVideo()
            }
            Button(languageService.phrase("Annuler"), role: .cancel) {
                discardPendingCommunityVideo()
            }
        } message: {
            Text(languageService.mediaSendConfirmationMessage)
        }
        .sheet(isPresented: $showCommunityLibrary, onDismiss: {
            selectedLibraryMediaItems = []
        }) {
            NavigationStack {
                LibraryMediaPicker(selectedItems: $selectedLibraryMediaItems)
                .navigationTitle(languageService.phrase("Galerie"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(languageService.phrase("Annuler")) {
                            selectedLibraryMediaItems = []
                            showCommunityLibrary = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(languageService.phrase("Envoyer")) {
                            guard !isPreparingLibraryMedia, !vm.isSending else { return }
                            let mediaItems = selectedLibraryMediaItems
                            isPreparingLibraryMedia = true
                            selectedLibraryMediaItems = []
                            showCommunityLibrary = false
                            Task { @MainActor in
                                defer { isPreparingLibraryMedia = false }
                                do {
                                    let mediaURLs = try await LibraryMediaLoader.loadFiles(from: mediaItems)
                                    vm.sendCapturedMediaBatch(communityId: communityId, fileURLs: mediaURLs)
                                } catch {
                                    vm.error = error.localizedDescription
                                }
                            }
                        }
                        .disabled(selectedLibraryMediaItems.isEmpty || isPreparingLibraryMedia || vm.isSending)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTorpilleCamera) {
            CameraMediaPicker(selectedFileURL: $torpilleFileURL, allowedTypes: .videoOnly)
        }
        .sheet(item: $reportingMessage) { message in
            ReportContentSheet(
                title: languageService.phrase("Signaler ce contenu"),
                reportedName: "@\(message.senderPseudo)",
                onCancel: {
                    reportingMessage = nil
                },
                onSubmit: { reason, details in
                    vm.reportMessage(communityId: communityId, message: message, reason: reason, details: details)
                    reportingMessage = nil
                }
            )
        }
        .alert(languageService.phrase("Bloquer cet utilisateur ?"), isPresented: Binding(
            get: { messagePendingSenderBlock != nil },
            set: { if !$0 { messagePendingSenderBlock = nil } }
        )) {
            Button(languageService.phrase("Annuler"), role: .cancel) {
                messagePendingSenderBlock = nil
            }
            Button(languageService.phrase("Bloquer"), role: .destructive) {
                if let message = messagePendingSenderBlock {
                    vm.blockSender(message: message)
                }
                messagePendingSenderBlock = nil
            }
        } message: {
            Text(languageService.phrase("Cet utilisateur sera masqué dans l'application. Pour le débloquer, va dans ton profil."))
        }
        .navigationDestination(isPresented: Binding(
            get: { vm.selectedPublicProfile != nil },
            set: { if !$0 { vm.selectedPublicProfile = nil } }
        )) {
            if let profile = vm.selectedPublicProfile {
                SharedPublicUserProfileView(profile: profile)
            }
        }
        .sheet(item: Binding(get: {
            playbackURL.map {
                PlaybackContainer(
                    url: $0,
                    mediaType: playbackMediaType,
                    title: playbackTitle,
                    sender: playbackSender,
                    tagX: playbackTagX,
                    tagY: playbackTagY
                )
            }
        }, set: { newValue in
            playbackURL = newValue?.url
            playbackMediaType = newValue?.mediaType ?? .video
            playbackTitle = newValue?.title
            playbackSender = newValue?.sender
            playbackTagX = newValue?.tagX
            playbackTagY = newValue?.tagY
        }), onDismiss: {
            finishUnseenTorpillePlaybackIfNeeded()
        }) { item in
            VideoPlayerSheet(
                url: item.url,
                mediaType: item.mediaType,
                overlayText: item.title,
                senderText: item.sender,
                tagX: item.tagX,
                tagY: item.tagY,
                allowsHoldToPause: unseenPlaybackIndex != nil,
                onTap: unseenPlaybackIndex == nil ? nil : { _ in
                    advanceUnseenTorpillePlayback()
                },
                onEnded: unseenPlaybackIndex == nil ? nil : {
                    advanceUnseenTorpillePlayback()
                },
                onDismissRequest: unseenPlaybackIndex == nil ? nil : {
                    finishUnseenTorpillePlaybackIfNeeded()
                }
            )
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
                    if torpilleCapturePurpose == .newTorpille {
                        torpilleFileURL = nil
                    }
                    torpilleRecipientQuery = ""
                    showTorpilleRecipientSheet = false
                },
                onSelectMember: { member in
                    if torpilleCapturePurpose == .response {
                        guard let responseFileURL,
                              vm.myMember?.pendingTorpilleId != nil else { return }
                        vm.respond(
                            communityId: communityId,
                            fileURL: responseFileURL,
                            nextTaggedMember: member,
                            publishToReels: false,
                            tagX: 0.5,
                            tagY: 0.2
                        )
                        self.responseFileURL = nil
                    } else {
                        guard let torpilleFileURL else { return }
                        vm.sendVideoTorpille(
                            communityId: communityId,
                            fileURL: torpilleFileURL,
                            taggedMember: member,
                            fallbackPseudoText: member.displayName,
                            publishToReels: false,
                            tagX: 0.5,
                            tagY: 0.2
                        )
                        self.torpilleFileURL = nil
                    }
                    torpilleRecipientQuery = ""
                    showTorpilleRecipientSheet = false
                }
            )
        }
        .onChange(of: selectedFileURL) { _, newValue in
            guard let newValue else { return }
            selectedFileURL = nil
            if communityVideoWasDiscarded {
                try? FileManager.default.removeItem(at: newValue)
                communityVideoWasDiscarded = false
            } else if communityVideoWasApproved {
                communityVideoWasApproved = false
                vm.sendCapturedMedia(communityId: communityId, fileURL: newValue)
            } else {
                if !showCommunityLibrary {
                    showCommunityVideoCamera = false
                }
                pendingCommunityVideoURL = newValue
            }
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
            if isLoadingMedia {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    TorpilleLoadingView(isLoadingMedia ? "Chargement du média…" : "Envoi…")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func approvePendingCommunityVideo() {
        showCommunityVideoConfirmation = false
        if let pendingURL = pendingCommunityVideoURL {
            pendingCommunityVideoURL = nil
            vm.sendCapturedMedia(communityId: communityId, fileURL: pendingURL)
        } else {
            communityVideoWasApproved = true
        }
    }

    private func discardPendingCommunityVideo() {
        showCommunityVideoConfirmation = false
        if let pendingURL = pendingCommunityVideoURL {
            try? FileManager.default.removeItem(at: pendingURL)
            pendingCommunityVideoURL = nil
        } else {
            communityVideoWasDiscarded = true
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        guard !vm.messages.isEmpty else { return }

        let action = {
            proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
            hasScrolledToBottomOnOpen = true
            hasCompletedInitialPositioning = true
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation {
                    action()
                }
            } else {
                action()
            }
        }
    }

    private func scrollToMessage(_ messageId: String, using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(messageId, anchor: .top)
            hasScrolledToBottomOnOpen = true
            hasCompletedInitialPositioning = true
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

    private func scrollOnOpen(using proxy: ScrollViewProxy) {
        guard !hasPerformedInitialUnreadPositioning else { return }
        hasPerformedInitialUnreadPositioning = true
        scrollToBottom(using: proxy, animated: false)
    }

    private func scrollToUnreadHeader(for messageId: String, using proxy: ScrollViewProxy, animated: Bool) {
        let headerId = unreadHeaderId(for: messageId)
        let action = {
            proxy.scrollTo(headerId, anchor: .top)
            hasScrolledToBottomOnOpen = true
            hasCompletedInitialPositioning = true
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

    private func handleMessagesCountChange(oldCount: Int, newCount: Int, using proxy: ScrollViewProxy) {
        let isFirstLoad = !hasScrolledToBottomOnOpen
        let didReceiveNewMessage = newCount > oldCount
        guard isFirstLoad || didReceiveNewMessage else { return }

        if isFirstLoad {
            scrollOnOpen(using: proxy)
            return
        }

        guard isAtBottom else { return }
        scrollToBottom(using: proxy, animated: true)
    }

    private func handleMessageAppear(index: Int) {
        guard vm.messages.indices.contains(index) else { return }
        guard hasCompletedInitialPositioning else { return }
        if index == vm.messages.count - 1 {
            isAtBottom = true
            vm.markMessagesSeenIfNeeded(communityId: communityId)
        }
    }

    private func handleMessageDisappear(index: Int) {
        guard vm.messages.indices.contains(index) else { return }
        if index == vm.messages.count - 1 {
            isAtBottom = false
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
            Text(vm.community?.name ?? "Communauté")
                .font(.headline)
                .lineLimit(1)
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
                Task { await startUnseenTorpillePlayback() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: vm.unseenTorpilles.isEmpty ? "bolt" : "bolt.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageService.phrase("Torpilles non vues"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(vm.unseenTorpilles.isEmpty ? languageService.phrase("Aucune nouvelle torpille") : languageService.toWatchLabel(vm.unseenTorpilles.count))
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
                    Text(languageService.phrase("Torpille"))
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
            Text(languageService.phrase("Torpille en attente"))
                .font(.subheadline.weight(.semibold))
            Text(languageService.replyToTorpilleLabel(pendingFrom))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let responseFileURL {
                Text(languageService.readyVideoLabel(responseFileURL.lastPathComponent))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(languageService.phrase("Filmer la réponse")) {
                    torpilleCapturePurpose = .response
                    showTorpilleCamera = true
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(ActionAccent.coral.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button(languageService.phrase("Relancer vers")) {
                    guard responseFileURL != nil,
                          vm.myMember?.pendingTorpilleId != nil else { return }
                    torpilleCapturePurpose = .response
                    torpilleRecipientQuery = ""
                    showTorpilleRecipientSheet = true
                }
                .disabled(responseFileURL == nil || vm.myMember?.pendingTorpilleId == nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ActionAccent.gold.tint.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        compactMessageRowContent(message)
            .contentShape(Rectangle())
            .onTapGesture {
                actionForMessage(message)?()
            }
            .contextMenu {
                saveMenuItem(for: message)
                safetyMenuItems(for: message)
            }
    }

    private func compactMessageRowContent(_ message: Message) -> some View {
        HStack(alignment: .center, spacing: 10) {
            messageLeadingBadge(for: message)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName(for: message))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.primary)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    if isTorpilleMessage(message) {
                        HStack(spacing: 4) {
                            Text("@\(message.senderPseudo)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("@\(message.taggedPseudo ?? "?")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(primaryPseudo(for: message))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    if message.type == "text", let text = message.text, !text.isEmpty {
                        Text(text)
                            .font(.caption)
                            .foregroundColor(Color(red: 0.45, green: 0.72, blue: 1.0))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    if message.isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ActionAccent.gold.tint)
                    }

                    if let createdAt = message.createdAt?.formattedHourMinute {
                        Text(createdAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUnread(message) ? Color(.systemGray5) : Color(.secondarySystemBackground))
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isUnread(message) ? 0.82 : 1)
    }

    @ViewBuilder
    private func saveMenuItem(for message: Message) -> some View {
        if message.isSaved {
            Label(languageService.phrase("Deja enregistre"), systemImage: "bookmark.fill")
        } else {
            Button {
                vm.saveMessage(communityId: communityId, message: message)
            } label: {
                Label(languageService.phrase("Enregistrer dans la discussion"), systemImage: "bookmark.fill")
            }
        }
    }

    @ViewBuilder
    private func safetyMenuItems(for message: Message) -> some View {
        if message.senderUid != vm.me?.uid {
            Divider()
            Button {
                reportingMessage = message
            } label: {
                Label(languageService.phrase("Signaler"), systemImage: "exclamationmark.bubble.fill")
            }
            Button {
                vm.hideContentFromSender(communityId: communityId, message: message)
            } label: {
                Label(languageService.phrase("Masquer ce membre ici"), systemImage: "eye.slash.fill")
            }
            Button(role: .destructive) {
                messagePendingSenderBlock = message
            } label: {
                Label(languageService.phrase("Bloquer cet utilisateur"), systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    private func iconName(for message: Message) -> String {
        if isTorpilleMessage(message) {
            switch message.type {
            case "video":
                return "bolt.fill"
            case "audio":
                return playingAudioMessageId == message.stableId ? "bolt.fill" : "bolt.waveform"
            case "image":
                return "bolt.badge.a"
            default:
                return "bolt.bubble.fill"
            }
        }

        switch message.type {
        case "video":
            return "video.fill"
        case "audio":
            return playingAudioMessageId == message.stableId ? "stop.fill" : "waveform"
        case "image":
            return "photo.fill"
        default:
            return "text.bubble.fill"
        }
    }

    private func isUnread(_ message: Message) -> Bool {
        let lastSeen = vm.unreadReferenceDate ?? .distantPast
        let createdAt = message.createdAt?.dateValue() ?? .distantPast
        return createdAt > lastSeen
    }

    private func isTorpilleMessage(_ message: Message) -> Bool {
        guard let taggedPseudo = message.taggedPseudo else { return false }
        return !taggedPseudo.isEmpty
    }

    private func primaryPseudo(for message: Message) -> String {
        if let taggedPseudo = message.taggedPseudo, !taggedPseudo.isEmpty {
            return "@\(taggedPseudo)"
        }
        return "@\(message.senderPseudo)"
    }


    @ViewBuilder
    private func messageLeadingBadge(for message: Message) -> some View {
        let member = vm.members.first { $0.uid == message.senderUid }
        let photoURL = member?.photoUrl ?? (vm.me?.uid == message.senderUid ? vm.me?.photoUrl : nil)
        let profileIcon = member?.profileIcon ?? (vm.me?.uid == message.senderUid ? vm.me?.profileIcon : nil)

        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.tertiarySystemBackground))

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.8)

            if let photoURL, !photoURL.isEmpty {
                ProfileAvatarImageView(
                    imageData: nil,
                    photoURL: photoURL,
                    fallbackSymbol: "person.fill",
                    size: 22,
                    fallbackIcon: profileIcon
                )
                .frame(width: 22, height: 22)
            } else {
                badgePlaceholder(profileIcon: profileIcon)
            }
        }
        .frame(width: 30, height: 30)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.openPublicProfile(for: message)
        }
    }

    private func badgePlaceholder(profileIcon: String? = nil) -> some View {
        ZStack {
            if let profileIcon, !profileIcon.isEmpty {
                Text(profileIcon)
                    .font(.system(size: 13))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }


    private func shouldShowDayHeader(for index: Int) -> Bool {
        guard vm.messages.indices.contains(index) else { return false }
        guard let currentDate = vm.messages[index].createdAt?.dateValue() else { return index == 0 }
        guard index > 0, let previousDate = vm.messages[index - 1].createdAt?.dateValue() else { return true }
        return !Calendar.current.isDate(currentDate, inSameDayAs: previousDate)
    }

    private func shouldShowUnreadHeader(for index: Int) -> Bool {
        guard vm.messages.indices.contains(index) else { return false }
        let message = vm.messages[index]
        return message.stableId == vm.firstUnreadMessageId
    }

    private func unreadHeaderId(for message: Message) -> String {
        unreadHeaderId(for: message.stableId)
    }

    private func unreadHeaderId(for messageId: String) -> String {
        "unread-header-\(messageId)"
    }

    private var retentionNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ActionAccent.gold.tint)
                .padding(.top, 1)

            Text(languageService.phrase("Les contenus sont automatiquement supprimés après 14 jours, sauf s'ils sont enregistrés dans les contenus enregistrés de la communauté."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ActionAccent.gold.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private func dayHeader(for message: Message) -> some View {
        HStack {
            Text(dayHeaderText(for: message.createdAt?.dateValue()))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private var unreadHeader: some View {
        HStack(spacing: 10) {
            Text(languageService.phrase("Messages non vus"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ActionAccent.coral.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(ActionAccent.coral.tint.opacity(0.12))
                .clipShape(Capsule())
            Rectangle()
                .fill(ActionAccent.coral.tint.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private func dayHeaderText(for date: Date?) -> String {
        guard let date else { return languageService.phrase("Date inconnue") }
        let formatter = DateFormatter()
        formatter.locale = languageService.locale
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    private func actionForMessage(_ message: Message) -> (() -> Void)? {
        switch message.type {
        case "video":
            return { Task { await playVideo(message: message) } }
        case "audio":
            return { Task { await playAudio(message: message) } }
        case "image":
            return { Task { await openImage(message: message) } }
        default:
            return nil
        }
    }

    private var bottomComposer: some View {
        VStack(spacing: 8) {
            if isPreparingLibraryMedia || vm.isSending {
                TorpilleLoadingView(languageService.phrase(isPreparingLibraryMedia ? "Chargement du média…" : "Envoi…"))
                    .frame(maxWidth: .infinity)
            }
            if audioRecorder.recordedFileURL != nil, !audioRecorder.isRecording {
                pendingVoiceMessageBar
            }

            HStack(spacing: 12) {
            if text.isEmpty {
                Button {
                    showCommunityCameraChoice = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(ActionAccent.ocean.gradient)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    isComposerFocused = false
                    showCommunityLibrary = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(ActionAccent.gold.gradient)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageService.phrase("Choisir des photos ou vidéos dans la galerie"))
                .disabled(isPreparingLibraryMedia || vm.isSending)
            }

            HStack(spacing: 8) {
                TextField(languageService.phrase("Écrire un message…"), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .layoutPriority(1)
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
            .layoutPriority(1)

            // Keep the stop control reachable if typing begins during recording.
            if text.isEmpty || audioRecorder.isRecording {
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
                .disabled(audioRecorder.recordedFileURL != nil && !audioRecorder.isRecording)
                .opacity(audioRecorder.recordedFileURL != nil && !audioRecorder.isRecording ? 0.45 : 1)
            }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var pendingVoiceMessageBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(ActionAccent.meadow.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(languageService.phrase("Message vocal prêt"))
                    .font(.subheadline.weight(.semibold))
                Text(formattedVoiceDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                audioRecorder.discardRecording()
            } label: {
                Label(languageService.phrase("Supprimer"), systemImage: "trash.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(languageService.phrase("Supprimer le message vocal"))

            Button {
                sendPendingVoiceMessage()
            } label: {
                Label(languageService.phrase("Envoyer"), systemImage: "paperplane.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(ActionAccent.meadow.tint)
            .accessibilityLabel(languageService.phrase("Envoyer le message vocal"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }

    private var formattedVoiceDuration: String {
        let totalSeconds = max(0, Int(audioRecorder.recordedDurationSeconds.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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
        return vm.torpilleTargetMembers.filter { $0.uid != myUID }
    }

    private func handleVoiceButton() {
        Task {
            do {
                if audioRecorder.isRecording {
                    _ = try audioRecorder.stopRecording()
                } else {
                    guard audioRecorder.recordedFileURL == nil else { return }
                    try await audioRecorder.startRecording()
                }
            } catch {
                vm.error = error.localizedDescription
            }
        }
    }

    private func sendPendingVoiceMessage() {
        guard let fileURL = audioRecorder.recordedFileURL else { return }
        let duration = audioRecorder.recordedDurationSeconds
        audioRecorder.clear()
        vm.sendAudioMessage(communityId: communityId, fileURL: fileURL, durationSeconds: duration)
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
            playbackSender = nil
            playbackTagX = message.tagX
            playbackTagY = message.tagY
        } catch {
            vm.error = error.localizedDescription
        }
    }

    @MainActor
    private func playTorpille(_ torpille: Torpille, reportError: Bool = true) async -> Bool {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let url = try await vm.resolvePlaybackURL(for: torpille)
            playbackURL = url
            playbackMediaType = .video
            playbackTitle = torpille.taggedPseudo
            playbackSender = torpille.fromPseudo.map { "@\($0)" }
            playbackTagX = torpille.tagX
            playbackTagY = torpille.tagY
            return true
        } catch {
            if reportError {
                vm.error = error.localizedDescription
            }
            return false
        }
    }

    @MainActor
    private func startUnseenTorpillePlayback() async {
        guard !vm.unseenTorpilles.isEmpty else { return }
        unseenPlaybackItems = vm.unseenTorpilles.sorted {
            ($0.createdAt?.dateValue() ?? .distantPast) < ($1.createdAt?.dateValue() ?? .distantPast)
        }
        unseenPlaybackIndex = nil
        unseenPlaybackLastSeenTimestamp = nil
        scheduleUnseenTorpillePlayback(at: 0)
    }

    @MainActor
    private func scheduleUnseenTorpillePlayback(at index: Int) {
        guard unseenPlaybackItems.indices.contains(index) else {
            playbackURL = nil
            finishUnseenTorpillePlaybackIfNeeded()
            return
        }

        unseenPlaybackIndex = index
        unseenPlaybackGeneration += 1
        let generation = unseenPlaybackGeneration
        unseenPlaybackLoadTask?.cancel()
        unseenPlaybackLoadTask = Task { @MainActor in
            await loadUnseenTorpille(startingAt: index, generation: generation)
        }
    }

    @MainActor
    private func loadUnseenTorpille(startingAt index: Int, generation: Int) async {
        var candidateIndex = index
        while unseenPlaybackItems.indices.contains(candidateIndex) {
            guard !Task.isCancelled, generation == unseenPlaybackGeneration else { return }
            unseenPlaybackIndex = candidateIndex
            let torpille = unseenPlaybackItems[candidateIndex]
            do {
                isLoadingMedia = true
                let url = try await vm.resolvePlaybackURL(for: torpille)
                guard !Task.isCancelled,
                      generation == unseenPlaybackGeneration,
                      unseenPlaybackIndex == candidateIndex else { return }
                playbackURL = url
                playbackMediaType = .video
                playbackTitle = torpille.taggedPseudo
                playbackSender = torpille.fromPseudo.map { "@\($0)" }
                playbackTagX = torpille.tagX
                playbackTagY = torpille.tagY
                isLoadingMedia = false
                return
            } catch {
                guard !Task.isCancelled, generation == unseenPlaybackGeneration else { return }
                candidateIndex += 1
            }
        }
        isLoadingMedia = false
        guard generation == unseenPlaybackGeneration else { return }
        playbackURL = nil
        finishUnseenTorpillePlaybackIfNeeded()
    }

    @MainActor
    private func advanceUnseenTorpillePlayback() {
        guard let currentIndex = unseenPlaybackIndex else { return }
        markUnseenTorpilleSeen(at: currentIndex)
        scheduleUnseenTorpillePlayback(at: currentIndex + 1)
    }

    private func markUnseenTorpilleSeen(at index: Int) {
        guard unseenPlaybackItems.indices.contains(index),
              let timestamp = unseenPlaybackItems[index].createdAt else {
            return
        }

        guard let currentTimestamp = unseenPlaybackLastSeenTimestamp else {
            unseenPlaybackLastSeenTimestamp = timestamp
            return
        }

        if timestamp.dateValue() > currentTimestamp.dateValue() {
            unseenPlaybackLastSeenTimestamp = timestamp
        }
    }

    private func finishUnseenTorpillePlaybackIfNeeded() {
        let timestamp = unseenPlaybackLastSeenTimestamp
        unseenPlaybackLoadTask?.cancel()
        unseenPlaybackLoadTask = nil
        unseenPlaybackGeneration += 1
        unseenPlaybackItems = []
        unseenPlaybackIndex = nil
        unseenPlaybackLastSeenTimestamp = nil
        isLoadingMedia = false
        guard let timestamp else { return }
        vm.markTorpillesSeen(communityId: communityId, upTo: timestamp)
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
            playbackSender = nil
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
            try MediaAudioSession.activatePlayback()
            let player = AVPlayer(url: url)
            player.isMuted = false
            player.volume = 1
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
    let url: URL
    let mediaType: MediaPlaybackType
    let title: String?
    let sender: String?
    let tagX: Double?
    let tagY: Double?

    var id: String { url.absoluteString }
}

private struct TorpilleRecipientSheet: View {
    @Binding var searchText: String
    let members: [Member]
    let onCancel: () -> Void
    let onSelectMember: (Member) -> Void
    @EnvironmentObject private var languageService: AppLanguageService

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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(languageService.phrase("Qui veux-tu torpiller ?"))
                    .font(.title3.weight(.semibold))

                Text(languageService.phrase("Choisis un membre de cette communauté. Son pseudo et sa photo sont visibles avant l'envoi."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField(languageService.phrase("Rechercher un membre"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if filteredMembers.isEmpty {
                            Text(languageService.phrase("Aucun membre ne correspond à cette recherche."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        ForEach(filteredMembers, id: \.uid) { member in
                            Button {
                                onSelectMember(member)
                            } label: {
                                HStack(spacing: 12) {
                                    if let photoURL = member.photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !photoURL.isEmpty {
                                        ProfileAvatarImageView(
                                            imageData: nil,
                                            photoURL: photoURL,
                                            fallbackSymbol: "person.crop.circle.fill",
                                            size: 42
                                        )
                                    } else if let profileIcon = member.profileIcon?.trimmingCharacters(in: .whitespacesAndNewlines),
                                              !profileIcon.isEmpty {
                                        EmojiAvatarView(profileIcon: profileIcon, size: 42)
                                    } else {
                                        ProfileAvatarImageView(
                                            imageData: nil,
                                            photoURL: nil,
                                            fallbackSymbol: "person.crop.circle.fill",
                                            size: 42
                                        )
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("@\(member.displayName)")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(languageService.phrase("Membre de la communauté. Touchez pour envoyer directement la torpille."))
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
            .navigationTitle(languageService.phrase("Choisir la cible"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageService.phrase("Annuler"), action: onCancel)
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
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        NavigationStack {
            List {
                if vm.unseenTorpilles.isEmpty {
                    ContentUnavailableView(languageService.phrase("Aucune torpille non vue"), systemImage: "bolt.slash")
                } else {
                    ForEach(vm.unseenTorpilles, id: \.stableId) { torpille in
                        Button {
                            Task { await playback(torpille) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(torpille.taggedPseudo.map { languageService.torpilleArrowLabel($0) } ?? languageService.phrase("Torpille"))
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
            .navigationTitle(languageService.phrase("Torpilles"))
        }
    }
}

struct ReportContentSheet: View {
    let title: String
    let reportedName: String
    let onCancel: () -> Void
    let onSubmit: (ReportReason, String) -> Void

    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(reportedName)
                        .font(.headline)
                    Picker(languageService.phrase("Raison"), selection: $reason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(languageService.phrase(reason.title)).tag(reason)
                        }
                    }
                } header: {
                    Text(languageService.phrase("Contenu concerné"))
                }

                Section {
                    TextField(languageService.phrase("Ajoute un contexte si nécessaire"), text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: details) { _, newValue in
                            if newValue.count > 1_000 {
                                details = String(newValue.prefix(1_000))
                            }
                        }
                    Text("\(details.count)/1 000")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text(languageService.phrase("Les signalements sont examinés rapidement. Les contenus abusifs peuvent être mis en quarantaine, supprimés et entraîner une suspension."))
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageService.phrase("Annuler"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(languageService.phrase("Envoyer")) {
                        onSubmit(reason, details)
                    }
                }
            }
        }
    }
}
