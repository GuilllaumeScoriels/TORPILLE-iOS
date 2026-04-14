import SwiftUI
import AVKit

struct VideoPlayerSheet: View {
    let url: URL
    let mediaType: MediaPlaybackType
    let overlayText: String?
    let senderText: String?
    let tagX: Double?
    let tagY: Double?
    let onTap: (() -> Void)?

    @State private var player: AVPlayer

    init(url: URL, mediaType: MediaPlaybackType = .video, overlayText: String?, senderText: String? = nil, tagX: Double?, tagY: Double?, onTap: (() -> Void)? = nil) {
        self.url = url
        self.mediaType = mediaType
        self.overlayText = overlayText
        self.senderText = senderText
        self.tagX = tagX
        self.tagY = tagY
        self.onTap = onTap
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if mediaType == .video {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        ProgressView()
                    }
                }

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

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
