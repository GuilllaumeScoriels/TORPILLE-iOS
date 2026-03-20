/**
 Fichier : VideoMessageRow.swift
 Rôle :
 - Affiche une ligne de message vidéo avec un bouton de lecture clair.

 Ce que fait ce fichier :
 - Reproduit l'intention du composant Android `VideoMessageItem`.
 - Affiche le pseudo tagué et déclenche la lecture au toucher.

 Pourquoi c'est utile :
 - Les boutons vidéo sont immédiatement actionnables dans la version iOS.
 */

import SwiftUI

struct VideoMessageRow: View {
    let message: Message
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack {
                Label {
                    Text(title)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.blue)
                }
                Spacer()
                Label("Lire", systemImage: "play.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if let taggedPseudo = message.taggedPseudo, !taggedPseudo.isEmpty {
            return "Vidéo → @\(taggedPseudo)"
        }
        return "Vidéo"
    }
}
