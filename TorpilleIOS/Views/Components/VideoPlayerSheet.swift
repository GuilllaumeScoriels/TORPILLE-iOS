/**
 Fichier : VideoPlayerSheet.swift
 Rôle :
 - Lit une vidéo dans un écran dédié avec overlay de tag.

 Ce que fait ce fichier :
 - Utilise `AVPlayer` pour la lecture native iOS.
 - Affiche un overlay textuel approximatif à partir des coordonnées relatives
   (`tagX`, `tagY`) comme dans l'écran Android.

 Pourquoi c'est utile :
 - Le bouton vidéo ouvre une vraie lecture intégrée côté iOS.
 */

import SwiftUI
import AVKit

struct VideoPlayerSheet: View {
    let url: URL
    let overlayText: String?
    let tagX: Double?
    let tagY: Double?

    @State private var player: AVPlayer

    init(url: URL, overlayText: String?, tagX: Double?, tagY: Double?) {
        self.url = url
        self.overlayText = overlayText
        self.tagX = tagX
        self.tagY = tagY
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }

                if let overlayText, let tagX, let tagY {
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
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
