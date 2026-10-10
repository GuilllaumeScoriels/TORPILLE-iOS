import SwiftUI

struct ReelsScreen: View {
    @StateObject private var vm: ReelsViewModel
    @ObservedObject private var languageService: AppLanguageService
    let onBack: (() -> Void)?

    @State private var playbackURL: URL?
    @State private var playbackReel: PublishedReel?
    @State private var playbackTitle: String?
    @State private var reportingReel: PublishedReel?
    @State private var blockingReel: PublishedReel?

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
                        CompactActionButton(title: languageService.phrase("Retour"), systemImage: "arrow.left.circle.fill", accent: .slate)
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
                                        Label(languageService.phrase("Retirer des Memories"), systemImage: "trash")
                                    }
                                } else if vm.canReport(reel) {
                                    Button {
                                        reportingReel = reel
                                    } label: {
                                        Label(languageService.phrase("Signaler"), systemImage: "exclamationmark.bubble.fill")
                                    }
                                    Button(role: .destructive) {
                                        blockingReel = reel
                                    } label: {
                                        Label(languageService.phrase("Bloquer cet utilisateur"), systemImage: "person.crop.circle.badge.xmark")
                                    }
                                }
                            }

                            if vm.canDelete(reel) {
                                Button(role: .destructive) {
                                    vm.removeFromMemories(reel)
                                } label: {
                                    Label(languageService.phrase("Retirer des Memories"), systemImage: "trash")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            } else if vm.canReport(reel) {
                                Button {
                                    reportingReel = reel
                                } label: {
                                    Label(languageService.phrase("Signaler"), systemImage: "exclamationmark.bubble.fill")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)

                                Button(role: .destructive) {
                                    blockingReel = reel
                                } label: {
                                    Label(languageService.phrase("Bloquer cet utilisateur"), systemImage: "person.crop.circle.badge.xmark")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let infoMessage = vm.infoMessage {
                    Text(languageService.localizedRuntimeMessage(infoMessage))
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let error = vm.error {
                    Text(languageService.localizedRuntimeMessage(error))
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(languageService.text(.reelsTitle))
        .sheet(item: $reportingReel) { reel in
            ReportContentSheet(
                title: languageService.phrase("Signaler ce contenu"),
                reportedName: "@\(reel.authorPseudo)",
                onCancel: { reportingReel = nil },
                onSubmit: { reason, details in
                    vm.report(reel, reason: reason, details: details)
                    reportingReel = nil
                }
            )
        }
        .alert(languageService.phrase("Bloquer cet utilisateur ?"), isPresented: Binding(
            get: { blockingReel != nil },
            set: { if !$0 { blockingReel = nil } }
        )) {
            Button(languageService.phrase("Annuler"), role: .cancel) {
                blockingReel = nil
            }
            Button(languageService.phrase("Bloquer"), role: .destructive) {
                guard let reel = blockingReel else { return }
                vm.blockAuthor(of: reel)
                blockingReel = nil
            }
        } message: {
            Text(languageService.phrase("Cet utilisateur sera masqué dans l'application. Pour le débloquer, va dans ton profil."))
        }
        .iosBackSwipe(enabled: onBack != nil) {
            onBack?()
        }
        .onAppear { vm.start() }
        .sheet(item: Binding(get: {
            playbackURL.map { PlaybackContainer(url: $0, mediaType: .video, title: playbackTitle, sender: nil, tagX: nil, tagY: nil) }
        }, set: { newValue in
            playbackURL = newValue?.url
            playbackTitle = newValue?.title
            if newValue == nil {
                playbackReel = nil
            }
        })) { item in
            VideoPlayerSheet(
                url: item.url,
                mediaType: .video,
                overlayText: item.title,
                authorPseudo: playbackReel?.authorPseudo,
                authorPhotoUrl: playbackReel?.authorPhotoUrl,
                authorProfileIcon: playbackReel?.authorProfileIcon,
                tagX: nil,
                tagY: nil,
                onAuthorTap: {
                    guard let playbackReel else { return }
                    openAuthorProfileAfterClosingPlayback(playbackReel)
                }
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { vm.selectedPublicProfile != nil },
            set: { if !$0 { vm.selectedPublicProfile = nil } }
        )) {
            if let profile = vm.selectedPublicProfile {
                SharedPublicUserProfileView(profile: profile)
            }
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
            playbackReel = reel
            playbackTitle = reel.taggedPseudo
        } catch {
            vm.error = error.localizedDescription
        }
    }

    @MainActor
    private func openAuthorProfileAfterClosingPlayback(_ reel: PublishedReel) {
        playbackURL = nil
        playbackReel = nil
        playbackTitle = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            vm.openPublicProfile(for: reel)
        }
    }
}
