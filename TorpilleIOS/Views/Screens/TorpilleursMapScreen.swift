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
        VStack(spacing: 12) {
            Text("Carte des torpilleurs")
                .font(.title2)
                .padding(.top)

            if vm.communities.isEmpty {
                ContentUnavailableView("Aucune communauté", systemImage: "map", description: Text("Tu n'appartiens encore à aucune communauté."))
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

                Map(coordinateRegion: $region, annotationItems: vm.annotations) { item in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)) {
                        VStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                            Text(item.pseudo)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
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
                    Text("La carte montre uniquement les torpilleurs de la communauté sélectionnée.")
                    Text("Chaque marqueur correspond à la dernière position connue enregistrée dans Firestore.")
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

            Spacer(minLength: 0)
        }
        .onAppear { vm.start() }
    }
}
