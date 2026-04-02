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

struct TorpilleursMapScreen: View {
    @StateObject private var vm: MapViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )
    @State private var selectedMember: MapMemberAnnotation?
    @State private var selectedCommunityIdForTorpille = ""
    @State private var torpilleFileURL: URL?
    @State private var showCommunityChooser = false

    init(env: AppEnvironment) {
        _vm = StateObject(wrappedValue: MapViewModel(repo: env.communityRepository, userRepository: env.userRepository, locationService: env.locationService))
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, 12)
            let bottomInset = max(proxy.safeAreaInsets.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    WelcomeHeroCard(
                        title: "Carte des torpilleurs",
                        subtitle: "Repère les membres actifs, filtre par communauté et envoie une torpille depuis la carte.",
                        primarySymbol: "map.fill",
                        secondarySymbol: "location.north.line.fill",
                        cornerSymbol: "paperplane.fill",
                        accent: .coral
                    )
                    .padding(.top, topInset + 4)
                    .padding(.horizontal)

                    if vm.communities.isEmpty {
                        ContentUnavailableView("Aucune communauté", systemImage: "map", description: Text("Tu n'appartiens encore à aucune communauté."))
                            .padding(.top, 24)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(vm.communities, id: \.stableId) { community in
                                    Button {
                                        vm.selectCommunity(community.stableId)
                                        if let first = vm.annotations.first {
                                            region.center = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
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

                        Toggle(isOn: $vm.showOnlyRecentlyConnected) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connectés il y a moins de 30 min")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(vm.visibleMembersCount) torpilleur(s) affiché(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)

                        Map(coordinateRegion: $region, annotationItems: vm.annotations) { item in
                            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)) {
                                MapUserAnnotationView(item: item) {
                                    handleMemberTap(item)
                                }
                            }
                        }
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)


                        VStack(alignment: .leading, spacing: 8) {
                            Text("Interprétation")
                                .font(.headline)

                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("La carte montre uniquement les torpilleurs de la communauté sélectionnée.")
                                    Text("Tu peux activer un filtre pour n'afficher que ceux dont la dernière position a été mise à jour dans les 30 dernières minutes.")
                                    Text("Chaque icône correspond à la dernière position connue enregistrée dans Firestore.")
                                    Text("L'heure affichée à côté de l'icône est celle de la dernière torpille de l'utilisateur concerné.")
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
                        Text(error)
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
                            Button("Torpiller dans \(community.name)") {
                                selectedCommunityIdForTorpille = community.stableId
                                torpilleFileURL = nil
                            }
                        }
                    }

                    Button("Annuler", role: .cancel) {
                        resetTorpilleSelection()
                    }
                }
                .sheet(isPresented: Binding(get: {
                    selectedMember != nil && !selectedCommunityIdForTorpille.isEmpty
                }, set: { isPresented in
                    if !isPresented {
                        resetTorpilleSelection()
                    }
                })) {
                    CameraMediaPicker(selectedFileURL: $torpilleFileURL, allowedTypes: .videoOnly)
                }
                .onChange(of: torpilleFileURL) { _, newValue in
                    guard let member = selectedMember, let newValue else { return }
                    vm.sendVideoTorpille(fileURL: newValue, to: member, in: selectedCommunityIdForTorpille)
                    resetTorpilleSelection()
                }
                .overlay {
                    if vm.isSendingTorpille {
                        ZStack {
                            Color.black.opacity(0.15).ignoresSafeArea()
                            ProgressView("Envoi de la torpille…")
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
        }
    }
}

private extension TorpilleursMapScreen {
    var sharedCommunitiesForSelectedMember: [Community] {
        guard let selectedMember else { return [] }
        return vm.sharedCommunities(with: selectedMember.id)
    }

    var torpilleCommunityDialogTitle: String {
        guard let selectedMember else {
            return "Choisir une communauté"
        }

        let count = sharedCommunitiesForSelectedMember.count
        if count <= 1 {
            return "Torpiller @\(selectedMember.pseudo)"
        }
        return "Choisir où torpiller @\(selectedMember.pseudo)"
    }

    func handleMemberTap(_ member: MapMemberAnnotation) {
        guard member.id != vm.currentUserId else { return }

        selectedMember = member
        let sharedCommunities = vm.sharedCommunities(with: member.id)

        if let selectedCommunity = sharedCommunities.first(where: { $0.stableId == vm.selectedCommunityId }) {
            if sharedCommunities.count == 1 {
                selectedCommunityIdForTorpille = selectedCommunity.stableId
            } else {
                showCommunityChooser = true
            }
            return
        }

        if let onlyCommunity = sharedCommunities.first, sharedCommunities.count == 1 {
            selectedCommunityIdForTorpille = onlyCommunity.stableId
        } else if !sharedCommunities.isEmpty {
            showCommunityChooser = true
        } else {
            vm.error = "Aucune communauté partagée avec @\(member.pseudo)."
            resetTorpilleSelection()
        }
    }

    func resetTorpilleSelection() {
        selectedMember = nil
        selectedCommunityIdForTorpille = ""
        torpilleFileURL = nil
        showCommunityChooser = false
    }
}

private struct MapUserAnnotationView: View {
    let item: MapMemberAnnotation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
            HStack(spacing: 6) {
                MapAvatarView(photoUrl: item.photoUrl, profileIcon: item.profileIcon)

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
        }
        .buttonStyle(.plain)
        .shadow(radius: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.pseudo), dernière torpille à \(item.lastTorpilleTimeText). \(item.subtitle)")
        .accessibilityHint("Touchez pour envoyer une torpille à cet utilisateur.")
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
