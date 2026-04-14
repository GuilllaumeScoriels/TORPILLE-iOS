import SwiftUI
import FirebaseCore
import AVFoundation

struct CommunityScreen: View {
    private static let bottomAnchorId = "community-bottom-anchor"

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
    @State private var playbackSender: String?
    @State private var playbackTagX: Double?
    @State private var playbackTagY: Double?
    @State private var isLoadingMedia = false

    @State private var audioPlayer: AVPlayer?
    @State private var playingAudioMessageId: String?

    @State private var showCommunityCamera = false
    @State private var showCommunityLibrary = false
    @State private var showTorpilleCamera = false
    @State private var showTorpilleRecipientSheet = false
    @State private var torpilleRecipientQuery = ""
    @State private var unseenPlaybackQueue: [Torpille] = []
    @State private var unseenPlaybackLastSeenTimestamp: Timestamp?
    @State private var hasScrolledToBottomOnOpen = false
    @State private var hasPerformedInitialUnreadPositioning = false
    @State private var hasCompletedInitialPositioning = false
    @State private var isAtBottom = true
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

            if let infoMessage = vm.infoMessage, !infoMessage.isEmpty {
                Text(infoMessage)
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

            /*if let error = vm.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }*/

            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    List {
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

            bottomComposer
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .navigationBarBackButtonHidden(true)
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
            audioRecorder.clear()
        }
        .sheet(isPresented: $showCommunityCamera) {
            CameraMediaPicker(selectedFileURL: $selectedFileURL, allowedTypes: .photoAndVideo)
        }
        .sheet(isPresented: $showCommunityLibrary) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    LibraryMediaPicker(selectedFileURL: $selectedFileURL)
                    Spacer()
                }
                .padding()
                .navigationTitle("Galerie")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            showCommunityLibrary = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showTorpilleCamera) {
            CameraMediaPicker(selectedFileURL: $torpilleFileURL, allowedTypes: .videoOnly)
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
                onTap: unseenPlaybackQueue.isEmpty ? nil : {
                    Task { await advanceUnseenTorpillePlayback() }
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
                        publishToReels: false,
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
                        publishToReels: false,
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
            showCommunityLibrary = false
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
            Text("Réponds à la torpille de @\(pendingFrom)!")
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
                            vm.respond(communityId: communityId, fileURL: responseFileURL, nextTaggedMember: member, publishToReels: false, tagX: 0.5, tagY: 0.2)
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

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        if let action = actionForMessage(message) {
            Button(action: action) {
                compactMessageRowContent(message)
            }
            .buttonStyle(.plain)
            .contextMenu {
                saveMenuItem(for: message)
            }
        } else {
            compactMessageRowContent(message)
                .contextMenu {
                    saveMenuItem(for: message)
                }
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
            Label("Deja enregistre", systemImage: "bookmark.fill")
        } else {
            Button {
                vm.saveMessage(communityId: communityId, message: message)
            } label: {
                Label("Enregistrer dans la discussion", systemImage: "bookmark.fill")
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
        let lastSeen = vm.unreadReferenceDate ?? vm.myMember?.lastSeenMessageAt?.dateValue() ?? .distantPast
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

        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.tertiarySystemBackground))

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.8)

            if let photoURL, let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    badgePlaceholder()
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
            } else {
                badgePlaceholder()
            }
        }
        .frame(width: 30, height: 30)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private func badgePlaceholder() -> some View {
        ZStack {
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
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
        guard isUnread(message) else { return false }
        guard index > 0 else { return true }
        return !isUnread(vm.messages[index - 1])
    }

    private func unreadHeaderId(for message: Message) -> String {
        unreadHeaderId(for: message.stableId)
    }

    private func unreadHeaderId(for messageId: String) -> String {
        "unread-header-\(messageId)"
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
            Text("Messages non vus")
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
        guard let date else { return "Date inconnue" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
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

            Button {
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
            playbackSender = nil
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
            playbackSender = torpille.fromPseudo.map { "@\($0)" }
            playbackTagX = torpille.tagX
            playbackTagY = torpille.tagY
        } catch {
            vm.error = error.localizedDescription
        }
    }

    @MainActor
    private func startUnseenTorpillePlayback() async {
        guard !vm.unseenTorpilles.isEmpty else { return }
        unseenPlaybackQueue = Array(vm.unseenTorpilles.dropFirst())
        unseenPlaybackLastSeenTimestamp = vm.unseenTorpilles.first?.createdAt
        if let first = vm.unseenTorpilles.first {
            await playTorpille(first)
        }
    }

    @MainActor
    private func advanceUnseenTorpillePlayback() async {
        guard !unseenPlaybackQueue.isEmpty else {
            playbackURL = nil
            finishUnseenTorpillePlaybackIfNeeded()
            return
        }

        let next = unseenPlaybackQueue.removeFirst()
        unseenPlaybackLastSeenTimestamp = next.createdAt ?? unseenPlaybackLastSeenTimestamp
        await playTorpille(next)
    }

    private func finishUnseenTorpillePlaybackIfNeeded() {
        guard let timestamp = unseenPlaybackLastSeenTimestamp else { return }
        unseenPlaybackQueue = []
        unseenPlaybackLastSeenTimestamp = nil
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
    let sender: String?
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

                Text("Tape un pseudo pour torpiller un ami.")
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
