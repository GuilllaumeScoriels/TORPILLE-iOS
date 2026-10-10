/**
 Fichier : TorpilleursMapScreen.swift
 Rôle :
 - Affiche la carte des torpilleurs, inspirée de l'écran Android ajouté.

 Ce que fait ce fichier :
 - Liste les communautés de l'utilisateur.
 - Montre les membres géolocalisés sur une carte MapKit.
 - Affiche la dernière position connue synchronisée automatiquement au démarrage de l'application.

 Pourquoi c'est utile :
 - La version iOS reprend la fonctionnalité carte demandée par l'utilisateur.
 */

import SwiftUI
import MapKit
import UIKit

struct TorpilleursMapScreen: View {
    @StateObject private var vm: MapViewModel
    @ObservedObject private var languageService: AppLanguageService
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
    )
    @State private var selectedMember: MapMemberAnnotation?
    @State private var selectedCommunityIdForTorpille = ""
    @State private var torpilleFileURL: URL?
    @State private var showCommunityChooser = false
    @State private var showTorpilleCamera = false

    init(env: AppEnvironment) {
        _languageService = ObservedObject(wrappedValue: env.languageService)
        _vm = StateObject(wrappedValue: MapViewModel(repo: env.communityRepository, userRepository: env.userRepository, locationService: env.locationService, languageService: env.languageService))
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, 12)
            let bottomInset = max(proxy.safeAreaInsets.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    WelcomeHeroCard(
                        title: languageService.phrase("Carte des torpilleurs"),
                        subtitle: nil,
                        primarySymbol: "map.fill",
                        secondarySymbol: "location.north.line.fill",
                        cornerSymbol: "paperplane.fill",
                        accent: .coral
                    )
                    .padding(.top, topInset + 4)
                    .padding(.horizontal)

                    if vm.communities.isEmpty {
                        ContentUnavailableView(languageService.phrase("Aucune communauté"), systemImage: "map", description: Text(languageService.phrase("Tu n'appartiens encore à aucune communauté.")))
                            .padding(.top, 24)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                Button {
                                    vm.selectCommunity("")
                                    if let first = vm.annotations.first {
                                        centerMap(on: first)
                                    }
                                } label: {
                                    CompactActionButton(
                                        title: languageService.phrase("Toutes"),
                                        systemImage: vm.selectedCommunityId.isEmpty ? "person.3.fill" : "person.3.sequence.fill",
                                        accent: vm.selectedCommunityId.isEmpty ? .ocean : .slate
                                    )
                                }
                                .buttonStyle(.plain)

                                ForEach(vm.communities, id: \.stableId) { community in
                                    Button {
                                        vm.selectCommunity(community.stableId)
                                        if let first = vm.annotations.first {
                                            centerMap(on: first)
                                        }
                                    } label: {
                                        CompactActionButton(
                                            title: community.name,
                                            systemImage: vm.selectedCommunityId == community.stableId ? "location.fill" : "location.circle.fill",
                                            accent: vm.selectedCommunityId == community.stableId ? .ocean : .slate
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }

                        Toggle(isOn: Binding(
                            get: { vm.isGhostMode },
                            set: { vm.setGhostMode($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(languageService.phrase("Mode fantôme"), systemImage: "eye.slash.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(languageService.phrase("Masque ta position et les autres utilisateurs sur la carte."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.purple)
                        .disabled(vm.isUpdatingGhostMode)
                        .padding(.horizontal)

                        Toggle(isOn: $vm.showOnlyRecentlyConnected) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(languageService.phrase("Connectés il y a moins de 30 min"))
                                    .font(.subheadline.weight(.semibold))
                                Text(languageService.visibleTorpilleursLabel(vm.visibleMembersCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(vm.isGhostMode)
                        .padding(.horizontal)

                        Map(position: $cameraPosition) {
                            if !vm.isGhostMode {
                                UserAnnotation()
                                ForEach(vm.annotations) { item in
                                Annotation(
                                    item.pseudo,
                                    coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude),
                                    anchor: .center
                                ) {
                                MapUserAnnotationView(
                                    item: item,
                                    canTorpille: item.id != vm.currentUserId,
                                    onAvatarTap: {
                                        openPublicProfile(for: item)
                                    },
                                    onTorpilleTap: {
                                        handleMemberTap(item)
                                    }
                                )
                            }
                            }
                        }
                        }
                        .mapStyle(.standard)
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)


                        VStack(alignment: .leading, spacing: 8) {
                            Text(languageService.phrase("Interprétation"))
                                .font(.headline)

                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if vm.isGhostMode {
                                        Text(languageService.phrase("Le mode fantôme est actif : ta position n'est pas partagée et aucun autre utilisateur n'apparaît sur ta carte."))
                                    } else {
                                        Text(vm.selectedCommunityId.isEmpty
                                             ? languageService.phrase("La carte montre tous les torpilleurs avec qui tu partages au moins une communauté.")
                                             : languageService.phrase("La carte montre uniquement les torpilleurs de la communauté sélectionnée."))
                                        Text(languageService.phrase("L'heure affichée à côté de l'icône est celle de la dernière torpille de l'utilisateur concerné."))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    if let error = vm.error {
                        Text(languageService.localizedRuntimeMessage(error))
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .confirmationDialog(
                    torpilleCommunityDialogTitle,
                    isPresented: $showCommunityChooser,
                    titleVisibility: .visible
                ) {
                    if let selectedMember {
                        ForEach(sharedCommunitiesForSelectedMember, id: \.stableId) { community in
                            Button(languageService.sendInCommunityLabel(community.name)) {
                                selectedCommunityIdForTorpille = community.stableId
                                showCommunityChooser = false
                                if let fileURL = torpilleFileURL {
                                    vm.sendVideoTorpille(fileURL: fileURL, to: selectedMember, in: community.stableId)
                                    resetTorpilleSelection()
                                } else {
                                    showTorpilleCamera = true
                                }
                            }
                        }
                    }

                    Button(languageService.phrase("Annuler"), role: .cancel) {
                        resetTorpilleSelection()
                    }
                }
                .sheet(isPresented: $showTorpilleCamera, onDismiss: {
                    if torpilleFileURL == nil {
                        resetTorpilleSelection()
                    }
                }) {
                    CameraMediaPicker(selectedFileURL: $torpilleFileURL, allowedTypes: .videoOnly)
                }
                .navigationDestination(isPresented: Binding(
                    get: { vm.selectedPublicProfile != nil },
                    set: { if !$0 { vm.selectedPublicProfile = nil } }
                )) {
                    if let profile = vm.selectedPublicProfile {
                        SharedPublicUserProfileView(profile: profile)
                    }
                }
                .onChange(of: torpilleFileURL) { _, newValue in
                    guard let member = selectedMember, let newValue else { return }

                    let sharedCommunities = sharedCommunitiesForSelectedMember
                    if !selectedCommunityIdForTorpille.isEmpty {
                        vm.sendVideoTorpille(fileURL: newValue, to: member, in: selectedCommunityIdForTorpille)
                        resetTorpilleSelection()
                    } else if sharedCommunities.count == 1, let onlyCommunity = sharedCommunities.first {
                        selectedCommunityIdForTorpille = onlyCommunity.stableId
                        vm.sendVideoTorpille(fileURL: newValue, to: member, in: onlyCommunity.stableId)
                        resetTorpilleSelection()
                    } else if sharedCommunities.count > 1 {
                        showCommunityChooser = true
                    } else {
                        vm.error = languageService.noSharedCommunityLabel(member.pseudo)
                        resetTorpilleSelection()
                    }
                }
                .overlay {
                    if vm.isSendingTorpille {
                        ZStack {
                            Color.black.opacity(0.15).ignoresSafeArea()
                            TorpilleLoadingView(languageService.phrase("Envoi de la torpille…"))
                                .padding()
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(.bottom, bottomInset + 24)
                .reserveMainTabBarSpace()
            }
            .onAppear {
                vm.start()
            }
            .onChange(of: vm.annotations) { _, annotations in
                fitMap(to: annotations)
            }
        }
    }
}

private extension TorpilleursMapScreen {
    func centerMap(on annotation: MapMemberAnnotation) {
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: annotation.latitude, longitude: annotation.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))
    }

    func fitMap(to annotations: [MapMemberAnnotation]) {
        guard !annotations.isEmpty else { return }

        if annotations.count == 1, let only = annotations.first {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: only.latitude, longitude: only.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            ))
            return
        }

        let latitudes = annotations.map(\.latitude)
        let longitudes = annotations.map(\.longitude)
        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let latitudeDelta = max(0.04, (maxLatitude - minLatitude) * 1.5)
        let longitudeDelta = max(0.04, (maxLongitude - minLongitude) * 1.5)
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }

    var sharedCommunitiesForSelectedMember: [Community] {
        guard let selectedMember else { return [] }
        return vm.sharedCommunities(with: selectedMember.id)
    }

    var torpilleCommunityDialogTitle: String {
        guard let selectedMember else {
            return languageService.phrase("Choisir une communauté")
        }

        let count = sharedCommunitiesForSelectedMember.count
        if count <= 1 {
            return languageService.torpilleUserLabel(selectedMember.pseudo)
        }
        return languageService.chooseWhereToTorpilleLabel(selectedMember.pseudo)
    }

    func handleMemberTap(_ member: MapMemberAnnotation) {
        guard member.id != vm.currentUserId else { return }

        selectedMember = member
        let sharedCommunities = vm.sharedCommunities(with: member.id)

        if sharedCommunities.isEmpty {
            vm.error = languageService.noSharedCommunityLabel(member.pseudo)
            resetTorpilleSelection()
            return
        }

        if sharedCommunities.count > 1 {
            selectedCommunityIdForTorpille = ""
            torpilleFileURL = nil
            showCommunityChooser = true
            return
        }

        if let selectedCommunity = sharedCommunities.first(where: { $0.stableId == vm.selectedCommunityId }) {
            selectedCommunityIdForTorpille = selectedCommunity.stableId
        } else if let onlyCommunity = sharedCommunities.first, sharedCommunities.count == 1 {
            selectedCommunityIdForTorpille = onlyCommunity.stableId
        } else {
            selectedCommunityIdForTorpille = ""
        }

        torpilleFileURL = nil
        showTorpilleCamera = true
    }

    func openPublicProfile(for member: MapMemberAnnotation) {
        guard member.id != vm.currentUserId else { return }
        vm.openPublicProfile(for: member)
    }

    func resetTorpilleSelection() {
        selectedMember = nil
        selectedCommunityIdForTorpille = ""
        torpilleFileURL = nil
        showCommunityChooser = false
        showTorpilleCamera = false
    }
}

private struct MapUserAnnotationView: View {
    let item: MapMemberAnnotation
    let canTorpille: Bool
    let onAvatarTap: () -> Void
    let onTorpilleTap: () -> Void
    @State private var isTorpilleActionVisible = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    MapAvatarView(photoUrl: item.photoUrl, profileIcon: item.profileIcon)
                    MapAnnotationGestureSurface(
                        onTap: onAvatarTap,
                        onLongPress: canTorpille ? revealTorpilleAction : nil
                    )
                }
                .frame(width: 48, height: 48)
                    .accessibilityAction(named: "Afficher l'action Torpille") {
                        guard canTorpille else { return }
                        revealTorpilleAction()
                    }

                if isTorpilleActionVisible && canTorpille {
                    ZStack {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(ActionAccent.coral.gradient)
                            .clipShape(Circle())
                        MapAnnotationGestureSurface(onTap: triggerTorpille, onLongPress: nil)
                    }
                    .frame(width: 38, height: 38)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if !item.lastTorpilleTimeText.isEmpty {
                Text(item.lastTorpilleTimeText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            Text(item.pseudo)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .shadow(radius: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(annotationAccessibilityLabel)
        .accessibilityHint("Touchez l'avatar pour ouvrir le profil public. Maintenez l'appui pour afficher l'action Torpille.")
    }

    private var annotationAccessibilityLabel: String {
        guard !item.lastTorpilleTimeText.isEmpty else {
            return "\(item.pseudo). \(item.subtitle)"
        }
        return "\(item.pseudo), dernière torpille à \(item.lastTorpilleTimeText). \(item.subtitle)"
    }

    private func revealTorpilleAction() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            isTorpilleActionVisible = true
        }
    }

    private func triggerTorpille() {
        isTorpilleActionVisible = false
        onTorpilleTap()
    }
}

/// UIKit owns these recognizers so MKMapView cannot swallow the annotation's touch.
private struct MapAnnotationGestureSurface: UIViewRepresentable {
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap))
        tap.cancelsTouchesInView = true
        view.addGestureRecognizer(tap)

        if onLongPress != nil {
            let longPress = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.didLongPress(_:))
            )
            longPress.minimumPressDuration = 0.45
            longPress.allowableMovement = 24
            longPress.cancelsTouchesInView = true
            tap.require(toFail: longPress)
            view.addGestureRecognizer(longPress)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onLongPress: (() -> Void)?

        init(onTap: @escaping () -> Void, onLongPress: (() -> Void)?) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        @objc func didTap() {
            onTap()
        }

        @objc func didLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            onLongPress?()
        }
    }
}

private struct MapAvatarView: View {
    let photoUrl: String?
    let profileIcon: String?

    var body: some View {
        Group {
            if let photoUrl, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
        .background(Circle().fill(Color.blue.opacity(0.18)))
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.18))
            Text(profileIcon ?? "🍺")
                .font(.system(size: 20))
        }
    }
}
