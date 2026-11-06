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
import UIKit
import UniformTypeIdentifiers

private struct ResponseTimePickerCard: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(languageService.phrase("Temps de réponse"))
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Picker(languageService.phrase("Heures"), selection: $hours) {
                    ForEach(0..<24, id: \.self) { value in
                        Text(languageService.hoursLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker(languageService.phrase("Minutes"), selection: $minutes) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(languageService.minutesLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(languageService.currentDelayLabel(formatResponseTime(Int64(hours * 3600 + minutes * 60))))
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
    @ObservedObject private var languageService: AppLanguageService
    let onCreated: (String) -> Void
    let onBack: () -> Void

    init(env: AppEnvironment, onCreated: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        self.onCreated = onCreated
        self.onBack = onBack
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: CreateCommunityViewModel(repo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeHeroCard(
                    title: languageService.phrase("Nouvelle communauté"),
                    subtitle: languageService.phrase("Crée un espace accueillant, règle son tempo et invite tes joueurs."),
                    primarySymbol: "person.3.fill",
                    secondarySymbol: "flag.checkered.2.crossed",
                    cornerSymbol: "plus.circle.fill",
                    accent: .sunset
                )

                VStack(alignment: .leading, spacing: 14) {
                    TextField(languageService.phrase("Nom"), text: $vm.name)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    ResponseTimePickerCard(hours: $vm.responseHours, minutes: $vm.responseMinutes)

                    Toggle(languageService.phrase("Communauté publique"), isOn: $vm.isPublic)
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
                        title: vm.isLoading ? languageService.phrase("Création…") : languageService.phrase("Créer"),
                        subtitle: nil,
                        systemImage: "plus.circle.fill",
                        illustrationSymbol: "person.3.sequence.fill",
                        accent: .meadow
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading || vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: onBack) {
                    CompactActionButton(title: languageService.phrase("Retour"), systemImage: "arrow.left.circle.fill", accent: .slate)
                }
                .buttonStyle(.plain)

                if let error = vm.error {
                    Text(languageService.localizedRuntimeMessage(error))
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
        .navigationTitle(languageService.phrase("Créer"))
        .iosBackSwipe {
            onBack()
        }
    }
}

struct JoinCommunityScreen: View {
    @StateObject private var vm: JoinCommunityViewModel
    @ObservedObject private var languageService: AppLanguageService
    let communityId: String
    let onJoined: () -> Void
    let onCancel: () -> Void

    init(env: AppEnvironment, communityId: String, onJoined: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.communityId = communityId
        self.onJoined = onJoined
        self.onCancel = onCancel
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: JoinCommunityViewModel(repo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        VStack(spacing: 18) {
            WelcomeHeroCard(
                title: languageService.phrase("Invitation communauté"),
                subtitle: languageService.phrase("Patiente un instant pendant que Torpille vérifie ton invitation."),
                primarySymbol: "envelope.open.fill",
                secondarySymbol: "person.2.badge.plus",
                cornerSymbol: "checkmark.circle.fill",
                accent: .ocean
            )

            if vm.loading { TorpilleLoadingView() }

            if let error = vm.error {
                Text(languageService.localizedRuntimeMessage(error))
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if let infoMessage = vm.infoMessage {
                Text(languageService.localizedRuntimeMessage(infoMessage))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            Button(action: onCancel) {
                CompactActionButton(title: languageService.phrase("Retour"), systemImage: "arrow.left.circle.fill", accent: .coral)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .iosBackSwipe {
            onCancel()
        }
        .task {
            await vm.join(communityId, onJoined: onJoined)
        }
    }
}

struct CommunityInfoScreen: View {
    @StateObject private var vm: CommunityInfoViewModel
    @ObservedObject private var languageService: AppLanguageService
    private let env: AppEnvironment
    let communityId: String
    let onBack: () -> Void
    let onLeft: () -> Void
    @State private var invitationCode: String?
    @State private var invitationCodeError: String?
    @State private var reportingMember: Member?
    @State private var memberPendingBlock: Member?
    @State private var showsLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var leaveError: String?
    @State private var showsDeleteCommunityConfirmation = false

    init(env: AppEnvironment, communityId: String, onBack: @escaping () -> Void, onLeft: @escaping () -> Void) {
        self.env = env
        self.communityId = communityId
        self.onBack = onBack
        self.onLeft = onLeft
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: CommunityInfoViewModel(repo: env.communityRepository, userRepo: env.userRepository))
    }

    var body: some View {
        List {
            Section {
                Button(action: onBack) {
                    CompactActionButton(title: languageService.phrase("Retour à la discussion"), systemImage: "arrow.left.circle.fill", accent: .slate)
                }
                .buttonStyle(.plain)

                Text(vm.community?.name ?? languageService.text(.savedReelsCommunity))
                    .font(.title2.weight(.bold))

                if let community = vm.community {
                    let link = invitationLink(for: community.stableId)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(languageService.invitationLinkLabel(""))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(link)
                            .font(.footnote)
                            .textSelection(.enabled)
                        Text(languageService.phrase("Code d’invitation"))
                            .font(.caption.weight(.semibold))
                        if let invitationCode {
                            Text(invitationCode).font(.title2.monospaced().bold()).textSelection(.enabled)
                            Button(languageService.phrase("Copier le code")) { UIPasteboard.general.string = invitationCode }
                                .buttonStyle(.bordered)
                        } else if let invitationCodeError {
                            Text(invitationCodeError).font(.caption).foregroundStyle(.red)
                            Button(languageService.phrase("Réessayer")) { Task { await loadInvitationCode() } }
                        } else { ProgressView() }
                        if let url = URL(string: link) {
                            ShareLink(item: url) {
                                Label(languageService.phrase("Partager le lien"), systemImage: "square.and.arrow.up")
                            }.buttonStyle(.borderedProminent)
                        }
                        Button {
                            UIPasteboard.general.string = link
                        } label: {
                            Label(languageService.copyInvitationLinkLabel, systemImage: "doc.on.doc.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(languageService.phrase("La page d’invitation permet de rejoindre cette communauté."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SavedCommunityMessagesScreen(env: env, communityId: communityId)
                    } label: {
                        HStack {
                            CompactActionButton(
                                title: languageService.phrase("Contenus enregistres"),
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
                    Text(languageService.localizedRuntimeMessage(infoMessage))
                        .foregroundStyle(.green)
                }
            }

            Section {
                Text(vm.community?.eliminationMode == true ? "Mode éliminatoire activé" : "Mode éliminatoire désactivé").font(.caption)
                Button("Quitter la communauté", role: .destructive) { showsLeaveConfirmation = true }.disabled(isLeaving)
                if let leaveError { Text(leaveError).foregroundStyle(.red) }
            }
            .alert("Quitter la communauté ?", isPresented: $showsLeaveConfirmation) {
                Button("Annuler", role: .cancel) {}
                Button("Quitter", role: .destructive) {
                    isLeaving = true
                    Task {
                        defer { isLeaving = false }
                        do { try await env.communityRepository.leaveCommunity(communityId: communityId); onLeft() }
                        catch { leaveError = userErrorMessage(error) }
                    }
                }
            } message: { Text("Si tu es administrateur, l’administration sera transférée à un autre membre.") }

            RankingScheduleSummary(schedule: vm.community?.rankingSchedule ?? RankingSchedule())
            if vm.canModerateMembers {
                Section(languageService.phrase("Paramètres")) {
                    Toggle(languageService.phrase("Communauté publique"), isOn: $vm.isPublic)
                    RankingScheduleEditor(schedule: $vm.rankingSchedule)
                    Toggle("Mode éliminatoire", isOn: $vm.eliminationMode)
                    Text("Pour les prochaines torpilles : une réponse hors délai entraîne une expulsion. Un retour reste possible.").font(.caption).foregroundStyle(.secondary)
                    ResponseTimePickerCard(hours: $vm.responseHours, minutes: $vm.responseMinutes)
                    Button {
                        vm.saveSettings(communityId: communityId)
                    } label: {
                        CompactActionButton(title: languageService.phrase("Enregistrer"), systemImage: "square.and.arrow.down.fill", accent: .meadow)
                    }
                    .buttonStyle(.plain)
                }

                Section(languageService.phrase("Zone dangereuse")) {
                    Button(role: .destructive) {
                        showsDeleteCommunityConfirmation = true
                    } label: {
                        Label(
                            vm.isDeletingCommunity
                                ? languageService.phrase("Suppression en cours…")
                                : languageService.phrase("Supprimer la communauté"),
                            systemImage: "trash.fill"
                        )
                    }
                    .disabled(vm.isDeletingCommunity)
                }
            }


            if vm.canModerateMembers, !vm.pendingJoinRequests.isEmpty {
                Section(languageService.phrase("Demandes pour rejoindre")) {
                    ForEach(vm.pendingJoinRequests) { request in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(request.requesterPseudo.isEmpty ? languageService.phrase("Utilisateur") : "@\(request.requesterPseudo)")
                                .font(.headline)
                            HStack {
                                Button {
                                    vm.resolveJoinRequest(request, accept: true)
                                } label: {
                                    Label(languageService.phrase("Accepter"), systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button(role: .destructive) {
                                    vm.resolveJoinRequest(request, accept: false)
                                } label: {
                                    Label(languageService.phrase("Refuser"), systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Section {
                Text(languageService.phrase("Participants"))
                    .font(.headline)

                if vm.members.isEmpty {
                    Text(languageService.phrase("Aucun participant pour le moment."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.members) { member in
                    HStack(spacing: 12) {
                        Button {
                            vm.openPublicProfile(for: member)
                        } label: {
                            if let profileIcon = member.profileIcon, !profileIcon.isEmpty {
                                EmojiAvatarView(profileIcon: profileIcon, size: 42)
                            } else {
                                ProfileAvatarImageView(
                                    imageData: nil,
                                    photoURL: member.photoUrl,
                                    fallbackSymbol: "person.fill",
                                    size: 42
                                )
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(member.displayName)
                                    .font(.headline)

                                if member.uid == vm.community?.adminUid {
                                    Text(languageService.phrase("Admin"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ActionAccent.ocean.tint)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(ActionAccent.ocean.tint.opacity(0.12))
                                        .clipShape(Capsule())
                                }

                                Spacer(minLength: 0)
                            }
                            Text(languageService.xpInCommunityLabel(member.xpInCommunity))
                                .font(.subheadline)
                            Text(languageService.phrase(member.pendingTorpilleId == nil ? "OK" : "Torpillé en attente"))
                                .font(.caption)
                                .foregroundStyle(member.pendingTorpilleId == nil ? .green : .orange)
                        }

                        Spacer(minLength: 0)

                        if member.uid != env.communityRepository.currentUID {
                            Menu {
                                participantActions(for: member)
                            } label: {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(ActionAccent.slate.tint)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel(languageService.actionsForMemberLabel(member.displayName))
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if member.uid != env.communityRepository.currentUID {
                            Button(role: .destructive) {
                                memberPendingBlock = member
                            } label: {
                                Label(languageService.phrase("Bloquer"), systemImage: "person.crop.circle.badge.xmark")
                            }

                            Button {
                                reportingMember = member
                            } label: {
                                Label(languageService.phrase("Signaler"), systemImage: "exclamationmark.bubble.fill")
                            }
                            .tint(.orange)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if member.uid != env.communityRepository.currentUID, !vm.isFriend(member) {
                            Button {
                                vm.sendFriendRequest(to: member)
                            } label: {
                                Label(languageService.phrase("Ajouter"), systemImage: "person.badge.plus")
                            }
                            .tint(ActionAccent.meadow.tint)
                        }
                    }
                    .contextMenu {
                        if member.uid != env.communityRepository.currentUID {
                            participantActions(for: member)
                        }

                        if vm.canModerateMembers, member.uid != vm.community?.adminUid {
                            Divider()
                            Button(role: .destructive) {
                                vm.banMember(communityId: communityId, member: member)
                            } label: {
                                Label(languageService.phrase("Bannir"), systemImage: "hand.raised.fill")
                            }
                        }
                    }
                }
                }
            }

            if let error = vm.error {
                Section { Text(languageService.localizedRuntimeMessage(error)).foregroundStyle(.red) }
            }
        }
        .navigationTitle(languageService.phrase("Infos communauté"))
        .iosBackSwipe {
            onBack()
        }
        .onAppear { vm.start(communityId: communityId) }
        .task(id: communityId) { await loadInvitationCode() }
        .navigationDestination(isPresented: Binding(
            get: { vm.selectedPublicProfile != nil },
            set: { if !$0 { vm.selectedPublicProfile = nil } }
        )) {
            if let profile = vm.selectedPublicProfile {
                SharedPublicUserProfileView(profile: profile)
            }
        }
        .sheet(item: $reportingMember) { member in
            ReportContentSheet(
                title: languageService.phrase("Signaler cet utilisateur"),
                reportedName: "@\(member.displayName)",
                onCancel: {
                    reportingMember = nil
                },
                onSubmit: { reason, details in
                    vm.reportMember(communityId: communityId, member: member, reason: reason, details: details)
                    reportingMember = nil
                }
            )
        }
        .alert(languageService.phrase("Bloquer cet utilisateur ?"), isPresented: Binding(
            get: { memberPendingBlock != nil },
            set: { if !$0 { memberPendingBlock = nil } }
        )) {
            Button(languageService.phrase("Annuler"), role: .cancel) {
                memberPendingBlock = nil
            }
            Button(languageService.phrase("Bloquer"), role: .destructive) {
                if let member = memberPendingBlock {
                    vm.blockMember(member)
                }
                memberPendingBlock = nil
            }
        } message: {
            Text(languageService.phrase("Cet utilisateur sera masqué dans l'application. Pour le débloquer, va dans ton profil."))
        }
        .alert(languageService.phrase("Supprimer cette communauté ?"), isPresented: $showsDeleteCommunityConfirmation) {
            Button(languageService.phrase("Annuler"), role: .cancel) {}
            Button(languageService.phrase("Supprimer définitivement"), role: .destructive) {
                vm.deleteCommunity(communityId: communityId, onDeleted: onBack)
            }
        } message: {
            Text(languageService.phrase("La communauté et tous ses contenus, enregistrés ou non, seront supprimés définitivement. Cette action est irréversible."))
        }
    }

    @ViewBuilder
    private func participantActions(for member: Member) -> some View {
        if !vm.isFriend(member) {
            Button {
                vm.sendFriendRequest(to: member)
            } label: {
                Label(languageService.phrase("Ajouter comme ami"), systemImage: "person.badge.plus")
            }
        }

        Button {
            reportingMember = member
        } label: {
            Label(languageService.phrase("Signaler cet utilisateur"), systemImage: "exclamationmark.bubble.fill")
        }

        if vm.isContentHidden(for: member) {
            Button {
                vm.showContentFromMember(communityId: communityId, member: member)
            } label: {
                Label(languageService.phrase("Réafficher ses contenus ici"), systemImage: "eye.fill")
            }
        } else {
            Button {
                vm.hideContentFromMember(communityId: communityId, member: member)
            } label: {
                Label(languageService.phrase("Masquer ses contenus ici"), systemImage: "eye.slash.fill")
            }
        }

        Button(role: .destructive) {
            memberPendingBlock = member
        } label: {
            Label(languageService.phrase("Bloquer cet utilisateur"), systemImage: "person.crop.circle.badge.xmark")
        }

        if vm.canModerateMembers, member.uid != vm.community?.adminUid {
            Divider()
            Button(role: .destructive) {
                vm.removeMember(communityId: communityId, member: member)
            } label: {
                Label(languageService.phrase("Retirer de la communauté"), systemImage: "person.crop.circle.badge.minus")
            }
        }
    }

    @MainActor
    private func loadInvitationCode() async {
        invitationCodeError = nil
        do { invitationCode = try await env.communityRepository.invitationCode(communityId: communityId) }
        catch { invitationCodeError = userErrorMessage(error) }
    }

    private func invitationLink(for communityId: String) -> String {
        let languageCode = languageService.effectiveLanguage.localeIdentifier
        return "https://torpille-38783.web.app/join.html?cid=\(communityId)&lang=\(languageCode)"
    }
}

struct SavedCommunityMessagesScreen: View {
    @State private var exportItem: SavedContentExport?
    @StateObject private var vm: SavedCommunityMessagesViewModel
    @EnvironmentObject private var languageService: AppLanguageService
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
                    languageService.phrase("Aucun contenu enregistre"),
                    systemImage: "bookmark.slash",
                    description: Text(languageService.phrase("Maintiens un contenu appuye dans la discussion pour l'enregistrer ici."))
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

                        HStack {
                            Button { Task { await export(message, save: false) } } label: {
                                Label("Partager", systemImage: "square.and.arrow.up")
                            }
                            Button { Task { await export(message, save: true) } } label: {
                                Label("Enregistrer sur l’appareil", systemImage: "arrow.down.doc")
                            }
                        }.buttonStyle(.borderless).disabled(isLoadingMedia)

                        if vm.canPublishToMemories(message) {
                            if vm.isPublishedInMemories(message) {
                                Button(role: .destructive) {
                                    vm.removeFromMemories(communityId: communityId, message: message)
                                } label: {
                                    Label(languageService.phrase("Retirer des Memories"), systemImage: "trash")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    vm.publishToMemories(communityId: communityId, message: message)
                                } label: {
                                    Label(languageService.phrase("Publier en Memories"), systemImage: "play.rectangle.fill")
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
                    Text(languageService.localizedRuntimeMessage(infoMessage))
                        .foregroundStyle(.green)
                }
            }

            if let error = vm.error {
                Section {
                    Text(languageService.localizedRuntimeMessage(error))
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(item: $exportItem) { SavedContentExportSheet(item: $0) }
        .navigationTitle(languageService.phrase("Contenus enregistres"))
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
                    TorpilleLoadingView(languageService.phrase("Chargement du media…"))
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

    @MainActor
    private func export(_ message: Message, save: Bool) async {
        guard !isLoadingMedia else { return }
        isLoadingMedia = true
        vm.error = nil
        defer { isLoadingMedia = false }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TorpilleExports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Retain recent exports so receiving apps can finish reading their copies.
            for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
                if let date = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: old) }
            }
            let destination: URL
            if message.type == "text" {
                destination = folder.appendingPathComponent("Torpille-\(UUID().uuidString).txt")
                try (message.text ?? "").write(to: destination, atomically: true, encoding: .utf8)
            } else {
                let remote = try await vm.resolvePlaybackURL(for: message)
                guard remote.scheme == "https" else { throw TorpilleError.missingData("Adresse du média invalide.") }
                let (temporary, response) = try await URLSession.shared.download(from: remote)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw TorpilleError.missingData("Impossible de télécharger ce contenu. Réessaie.")
                }
                let fallback = message.type == "image" ? "jpg" : message.type == "audio" ? "m4a" : "mp4"
                let ext = response.mimeType.flatMap { mime in
                    mime.hasPrefix(message.type + "/") ? UTType(mimeType: mime)?.preferredFilenameExtension : nil
                } ?? fallback
                destination = folder.appendingPathComponent("Torpille-\(UUID().uuidString).\(ext)")
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            exportItem = SavedContentExport(url: destination, save: save)
        } catch { vm.error = userErrorMessage(error) }
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
                    Text(languageService.savedAtLabel(savedAt.formatted(date: .abbreviated, time: .shortened)))
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
            return message.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message.text! : languageService.phrase("Message texte")
        case "image":
            return languageService.phrase("Image")
        case "video":
            if let taggedPseudo = message.taggedPseudo, !taggedPseudo.isEmpty {
                return languageService.videoForUserLabel(taggedPseudo)
            }
            return languageService.phrase("Video")
        case "audio":
            return languageService.phrase("Message vocal")
        default:
            return languageService.phrase("Contenu")
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
            vm.error = userErrorMessage(error)
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
            vm.error = userErrorMessage(error)
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
            try MediaAudioSession.activatePlayback()
            let player = AVPlayer(url: url)
            player.isMuted = false
            player.volume = 1
            audioPlayer?.pause()
            audioPlayer = player
            playingAudioMessageId = message.stableId
            player.play()
        } catch {
            vm.error = userErrorMessage(error)
        }
    }
}

private struct SavedMessagesStoriesViewer: View {
    @ObservedObject var vm: SavedCommunityMessagesViewModel
    @EnvironmentObject private var languageService: AppLanguageService
    let communityId: String
    let messages: [Message]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if messages.isEmpty {
                ContentUnavailableView(languageService.phrase("Aucun contenu enregistre"), systemImage: "bookmark.slash")
                    .foregroundStyle(.white)
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(messages.enumerated()), id: \.element.stableId) { index, message in
                        SavedStoryPage(message: message, vm: vm)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

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
                            closeViewer()
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
                                    Label(languageService.phrase("Retirer"), systemImage: "trash")
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
                                    Label(languageService.phrase("Publier"), systemImage: "sparkles.tv.fill")
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
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    let verticalMovement = value.translation.height
                    let horizontalMovement = abs(value.translation.width)
                    guard verticalMovement > 90, verticalMovement > horizontalMovement * 1.2 else { return }
                    closeViewer()
                }
        )
        .onAppear {
            selection = min(max(initialIndex, 0), max(messages.count - 1, 0))
        }
    }

    private func closeViewer() {
        dismiss()
    }

    private func storySummary(for message: Message) -> String {
        switch message.type {
        case "text":
            return message.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message.text! : languageService.phrase("Message texte")
        case "image":
            return languageService.phrase("Photo enregistree")
        case "video":
            return languageService.phrase(message.torpilleId?.isEmpty == false ? "Torpille enregistree" : "Video enregistree")
        case "audio":
            return languageService.phrase("Message vocal enregistre")
        default:
            return languageService.phrase("Contenu enregistre")
        }
    }
}

private struct SavedStoryPage: View {
    let message: Message
    @ObservedObject var vm: SavedCommunityMessagesViewModel
    @EnvironmentObject private var languageService: AppLanguageService

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
            TorpilleLoadingView(languageService.phrase("Chargement…"))
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
                TorpilleLoadingView(languageService.phrase("Chargement…"))
                    .tint(.white)
            }
        } else if isLoading {
            TorpilleLoadingView(languageService.phrase("Chargement…"))
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

            Text(languageService.phrase("Message vocal"))
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
                Label(languageService.phrase(isAudioPlaying ? "Pause" : "Ecouter"), systemImage: isAudioPlaying ? "pause.fill" : "play.fill")
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

            Text(message.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message.text! : languageService.phrase("Message texte"))
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
            loadingError = userErrorMessage(error)
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
                loadingError = userErrorMessage(error)
            }
        }
    }
}

private struct SavedContentExport: Identifiable {
    let id = UUID()
    let url: URL
    let save: Bool
}
private struct SavedContentExportSheet: UIViewControllerRepresentable {
    let item: SavedContentExport
    func makeUIViewController(context: Context) -> UIViewController {
        if item.save { return UIDocumentPickerViewController(forExporting: [item.url], asCopy: true) }
        let controller = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private struct RankingScheduleEditor: View {
    @Binding var schedule: RankingSchedule
    private let days = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    var body: some View {
        Toggle("Activer le classement à temps plein", isOn: $schedule.fullTime)
        if !schedule.fullTime {
            Picker("Fuseau horaire", selection: $schedule.timeZone) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }
            Text("Le classement et les nouvelles torpilles sont actifs pendant l’un des créneaux ci-dessous. Les créneaux hebdomadaires peuvent traverser minuit.").font(.caption)
            ForEach(schedule.weekly.indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    Picker("Jour", selection: $schedule.weekly[index].day) {
                        ForEach(1...7, id: \.self) { Text(days[$0 - 1]).tag($0) }
                    }
                    DatePicker("Début", selection: minuteBinding(index, start: true), displayedComponents: .hourAndMinute)
                    DatePicker("Fin", selection: minuteBinding(index, start: false), displayedComponents: .hourAndMinute)
                    Button("Toute la journée") {
                        schedule.weekly[index].startMinute = 0
                        schedule.weekly[index].endMinute = 1440
                    }.buttonStyle(.borderless)
                    Button("Supprimer ce créneau", role: .destructive) { schedule.weekly.remove(at: index) }.buttonStyle(.borderless)
                }.environment(\.timeZone, RankingClockTime.timeZone)
            }
            Button("Ajouter un créneau hebdomadaire") { schedule.weekly.append(WeeklyRankingWindow()) }
                .disabled(schedule.weekly.count >= 28)
            ForEach(schedule.dates.indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    DatePicker("Du", selection: dateBinding(index, start: true))
                    DatePicker("Au", selection: dateBinding(index, start: false))
                    Button("Supprimer cette période", role: .destructive) { schedule.dates.remove(at: index) }
                }.environment(\.timeZone, TimeZone(identifier: schedule.timeZone) ?? .current)
            }
            Button("Ajouter une période datée") { schedule.dates.append(DatedRankingWindow()) }
                .disabled(schedule.dates.count >= 30)
            Text("Hors horaires : pas de nouvelle torpille ni de points. Les réponses restent possibles et ne relancent aucune obligation. Les pénalités et expulsions attendent la réouverture.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func minuteBinding(_ index: Int, start: Bool) -> Binding<Date> {
        Binding(get: {
            guard schedule.weekly.indices.contains(index) else { return RankingClockTime.date(minutes: 0) }
            let value = start ? schedule.weekly[index].startMinute : schedule.weekly[index].endMinute
            return RankingClockTime.date(minutes: value)
        }, set: {
            guard schedule.weekly.indices.contains(index) else { return }
            let value = RankingClockTime.minutes(in: $0)
            if start { schedule.weekly[index].startMinute = value } else { schedule.weekly[index].endMinute = value }
        })
    }
    private func dateBinding(_ index: Int, start: Bool) -> Binding<Date> {
        Binding(get: {
            guard schedule.dates.indices.contains(index) else { return Date() }
            return Date(timeIntervalSince1970: Double(start ? schedule.dates[index].startMs : schedule.dates[index].endMs) / 1000)
        }, set: {
                    guard schedule.dates.indices.contains(index) else { return }
                    let value = Int64($0.timeIntervalSince1970 * 1000)
                    if start { schedule.dates[index].startMs = value } else { schedule.dates[index].endMs = value }
                })
    }
}

private struct RankingScheduleSummary: View {
    let schedule: RankingSchedule
    private let days = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    private func time(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
    private func dateLabel(_ milliseconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: schedule.timeZone)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
    }
    var body: some View {
        Section("Horaires du classement") {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(schedule.isActive(at: context.date) ? "Classement et torpilles actifs" : "Hors horaires · réponses uniquement")
            }
            if schedule.fullTime { Text("Actif à temps plein") }
            else {
                Text("Fuseau : \(schedule.timeZone)").font(.caption)
                ForEach(schedule.weekly.indices, id: \.self) { i in
                    let w = schedule.weekly[i]
                    Text("\(days[max(0, min(6, w.day - 1))]) · \(time(w.startMinute)) – \(time(w.endMinute))\(w.endMinute < w.startMinute ? " (lendemain)" : "")")
                }
                ForEach(schedule.dates.indices, id: \.self) { i in
                    Text("\(dateLabel(schedule.dates[i].startMs)) – \(dateLabel(schedule.dates[i].endMs))")
                }
            }
        }
    }
}
