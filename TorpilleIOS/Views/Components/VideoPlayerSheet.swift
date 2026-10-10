import SwiftUI
import AVKit

enum VideoPlayerTapRegion {
    case left
    case right
}

struct VideoPlayerSheet: View {
    let url: URL
    let mediaType: MediaPlaybackType
    let overlayText: String?
    let senderText: String?
    let authorPseudo: String?
    let authorPhotoUrl: String?
    let authorProfileIcon: String?
    let tagX: Double?
    let tagY: Double?
    let allowsHoldToPause: Bool
    let onTap: ((VideoPlayerTapRegion) -> Void)?
    let onAuthorTap: (() -> Void)?
    let onEnded: (() -> Void)?
    let onDismissRequest: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var holdRecognitionTask: Task<Void, Never>?
    @State private var isTouchActive = false
    @State private var isPausedByHold = false

    init(
        url: URL,
        mediaType: MediaPlaybackType = .video,
        overlayText: String?,
        senderText: String? = nil,
        authorPseudo: String? = nil,
        authorPhotoUrl: String? = nil,
        authorProfileIcon: String? = nil,
        tagX: Double?,
        tagY: Double?,
        allowsHoldToPause: Bool = false,
        onTap: ((VideoPlayerTapRegion) -> Void)? = nil,
        onAuthorTap: (() -> Void)? = nil,
        onEnded: (() -> Void)? = nil,
        onDismissRequest: (() -> Void)? = nil
    ) {
        self.url = url
        self.mediaType = mediaType
        self.overlayText = overlayText
        self.senderText = senderText
        self.authorPseudo = authorPseudo
        self.authorPhotoUrl = authorPhotoUrl
        self.authorProfileIcon = authorProfileIcon
        self.tagX = tagX
        self.tagY = tagY
        self.allowsHoldToPause = allowsHoldToPause
        self.onTap = onTap
        self.onAuthorTap = onAuthorTap
        self.onEnded = onEnded
        self.onDismissRequest = onDismissRequest
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if mediaType == .video {
                    VideoPlayer(player: player)
                        .onAppear { configurePlayer() }
                        .onDisappear {
                            holdRecognitionTask?.cancel()
                            player.pause()
                            player.replaceCurrentItem(with: nil)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: nil)) { notification in
                            guard let finishedItem = notification.object as? AVPlayerItem, finishedItem == player.currentItem else { return }
                            onEnded?()
                        }
                } else {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        TorpilleLoadingView()
                    }
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateHoldRecognition(for: value)
                            }
                            .onEnded { value in
                                isTouchActive = false
                                holdRecognitionTask?.cancel()
                                holdRecognitionTask = nil

                                if isPausedByHold {
                                    isPausedByHold = false
                                    player.play()
                                    return
                                }

                                if shouldDismiss(for: value) {
                                    player.pause()
                                    onDismissRequest?()
                                    dismiss()
                                    return
                                }

                                guard isTap(value) else { return }
                                let region: VideoPlayerTapRegion = value.location.x < geometry.size.width / 2 ? .left : .right
                                onTap?(region)
                            }
                    )

                if let overlayText, let tagX, let tagY, mediaType == .video {
                    Text(overlayText)
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .position(
                            x: max(30, min(geometry.size.width - 30, geometry.size.width * tagX)),
                            y: max(30, min(geometry.size.height - 30, geometry.size.height * tagY))
                        )
                }

                if let senderText, !senderText.isEmpty, mediaType == .video {
                    Text(senderText)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 18)
                        .padding(.leading, 18)
                }

                if let authorPseudo, !authorPseudo.isEmpty, mediaType == .video {
                    Button {
                        onAuthorTap?()
                    } label: {
                        HStack(spacing: 10) {
                            MemoryAuthorAvatar(photoURL: authorPhotoUrl, profileIcon: authorProfileIcon, size: 42)
                            Text("@\(authorPseudo)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                    .padding(.leading, 18)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task(id: url) {
            if mediaType == .video {
                configurePlayer()
            }
        }
    }

    private func configurePlayer() {
        holdRecognitionTask?.cancel()
        holdRecognitionTask = nil
        isTouchActive = false
        isPausedByHold = false
        try? MediaAudioSession.activatePlayback()
        player.isMuted = false
        player.volume = 1
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 3
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        player.seek(to: .zero)
        player.play()
    }

    private func updateHoldRecognition(for value: DragGesture.Value) {
        guard allowsHoldToPause, mediaType == .video else { return }

        isTouchActive = true
        let movedTooFar = abs(value.translation.width) >= 12 || abs(value.translation.height) >= 12
        if movedTooFar {
            holdRecognitionTask?.cancel()
            holdRecognitionTask = nil
            return
        }

        guard holdRecognitionTask == nil, !isPausedByHold else { return }
        holdRecognitionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, isTouchActive else { return }
            isPausedByHold = true
            player.pause()
        }
    }

    private func shouldDismiss(for value: DragGesture.Value) -> Bool {
        value.translation.height > 80
            && abs(value.translation.height) > abs(value.translation.width) * 1.4
    }

    private func isTap(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) < 12
            && abs(value.translation.height) < 12
    }
}

private struct MemoryAuthorAvatar: View {
    let photoURL: String?
    let profileIcon: String?
    let size: CGFloat

    var body: some View {
        if let photoURL,
           let url = URL(string: photoURL),
           !photoURL.isEmpty {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
        } else if let profileIcon, !profileIcon.isEmpty {
            EmojiAvatarView(profileIcon: profileIcon, size: size)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
    }
}
