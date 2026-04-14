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
            .background(Color(.tertiarySystemBackground))
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

struct ImageMessageRow: View {
    let message: Message
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label("Photo", systemImage: "photo.fill")
                    .foregroundStyle(.primary)
                Spacer()
                Text("Ouvrir")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct AudioMessageRow: View {
    let message: Message
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? .red : .green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Vocal de \(message.senderPseudo)")
                        .foregroundStyle(.primary)
                    Text(durationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(isPlaying ? "Arrêter" : "Lire")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var durationText: String {
        guard let seconds = message.audioDurationSeconds else {
            return "Durée inconnue"
        }
        let total = max(Int(seconds.rounded()), 0)
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}
