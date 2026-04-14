import SwiftUI

struct ReelsScreen: View {
    @StateObject private var vm: ReelsViewModel
    @ObservedObject private var languageService: AppLanguageService
    let onBack: (() -> Void)?

    @State private var playbackURL: URL?
    @State private var playbackTitle: String?

    init(env: AppEnvironment, onBack: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: ReelsViewModel(repo: env.communityRepository))
        _languageService = ObservedObject(wrappedValue: env.languageService)
        self.onBack = onBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let onBack {
                    Button(action: onBack) {
                        CompactActionButton(title: "Retour", systemImage: "arrow.left.circle.fill", accent: .slate)
                    }
                    .buttonStyle(.plain)
                }

                WelcomeHeroCard(
                    title: languageService.text(.reelsTitle),
                    subtitle: languageService.text(.reelsSubtitle),
                    primarySymbol: "play.rectangle.fill",
                    secondarySymbol: "sparkles.tv.fill",
                    cornerSymbol: "flame.fill",
                    accent: .coral
                )

                if vm.reels.isEmpty {
                    ContentUnavailableView(
                        languageService.text(.noReelsTitle),
                        systemImage: "play.slash",
                        description: Text(languageService.text(.noReelsDescription))
                    )
                } else {
                    ForEach(vm.reels, id: \.stableId) { reel in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                Task { await open(reel) }
                            } label: {
                                reelCard(reel)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if vm.canDelete(reel) {
                                    Button(role: .destructive) {
                                        vm.removeFromMemories(reel)
                                    } label: {
                                        Label("Retirer des Memories", systemImage: "trash")
                                    }
                                }
                            }

                            if vm.canDelete(reel) {
                                Button(role: .destructive) {
                                    vm.removeFromMemories(reel)
                                } label: {
                                    Label("Retirer des Memories", systemImage: "trash")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }

                if let infoMessage = vm.infoMessage {
                    Text(infoMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let error = vm.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(languageService.text(.reelsTitle))
        .onAppear { vm.start() }
        .sheet(item: Binding(get: {
            playbackURL.map { PlaybackContainer(url: $0, mediaType: .video, title: playbackTitle, sender: nil, tagX: nil, tagY: nil) }
        }, set: { newValue in
            playbackURL = newValue?.url
            playbackTitle = newValue?.title
        })) { item in
            VideoPlayerSheet(url: item.url, mediaType: .video, overlayText: item.title, tagX: nil, tagY: nil)
        }
    }

    private func reelCard(_ reel: PublishedReel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.57, blue: 0.33),
                                Color(red: 0.89, green: 0.23, blue: 0.34),
                                Color(red: 0.18, green: 0.12, blue: 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 260)

                VStack(alignment: .leading, spacing: 10) {
                    Text(languageService.text(.publishedBadge))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("@\(reel.authorPseudo)")
                                .font(.title3.weight(.black))
                                .foregroundStyle(.white)
                            Text("\(languageService.text(.savedReelsCommunity)) · \(reel.communityName)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            if let taggedPseudo = reel.taggedPseudo, !taggedPseudo.isEmpty {
                                Text("→ @\(taggedPseudo)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                .padding(22)
                .frame(height: 260)
            }

            if let publishedAt = reel.publishedAt?.dateValue() {
                Text(publishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func open(_ reel: PublishedReel) async {
        do {
            playbackURL = try await vm.resolvePlaybackURL(for: reel)
            playbackTitle = reel.taggedPseudo
        } catch {
            vm.error = error.localizedDescription
        }
    }
}
