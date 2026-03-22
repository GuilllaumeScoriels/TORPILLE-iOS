/**
 Fichier : TorpilleursMapScreen.swift
 Rôle :
 - Affiche la carte des torpilleurs, inspirée de l'écran Android ajouté.

 Ce que fait ce fichier :
 - Liste les communautés de l'utilisateur.
 - Montre les membres géolocalisés sur une carte MapKit.
 - Permet de pousser la position courante de l'utilisateur vers Firestore.

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

    init(env: AppEnvironment) {
        _vm = StateObject(wrappedValue: MapViewModel(repo: env.communityRepository, locationService: env.locationService))
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, 12)
            let bottomInset = max(proxy.safeAreaInsets.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    Text("Carte des torpilleurs")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, topInset + 4)
                        .padding(.horizontal)

                    if vm.communities.isEmpty {
                        ContentUnavailableView("Aucune communauté", systemImage: "map", description: Text("Tu n'appartiens encore à aucune communauté."))
                            .padding(.top, 24)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(vm.communities, id: \.stableId) { community in
                                    Button(community.name) {
                                        vm.selectCommunity(community.stableId)
                                        if let first = vm.annotations.first {
                                            region.center = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(vm.selectedCommunityId == community.stableId ? .blue : .gray)
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
                                MapUserAnnotationView(item: item)
                            }
                        }
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                        Button("Mettre à jour ma position") {
                            vm.refreshLocation()
                        }
                        .buttonStyle(.borderedProminent)

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
                .padding(.bottom, bottomInset + 72)
            }
            .onAppear {
                vm.start()
                vm.refreshLocation()
            }
        }
    }
}

private struct MapUserAnnotationView: View {
    let item: MapMemberAnnotation

    var body: some View {
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
        .shadow(radius: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.pseudo), dernière torpille à \(item.lastTorpilleTimeText). \(item.subtitle)")
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
