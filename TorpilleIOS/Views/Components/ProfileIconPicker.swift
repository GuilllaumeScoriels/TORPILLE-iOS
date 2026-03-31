import SwiftUI
import PhotosUI

struct ProfileIconLibrary {
    static let featuredIcons = [
        "🍺", "🍻", "🎯", "🚀", "⚡️", "🔥", "🌊", "⭐️",
        "🦈", "🐬", "🦊", "🐻", "🐼", "🐯", "🦁", "🐸",
        "🐵", "🦄", "🐙", "🦉", "🍀", "🌈", "🍕", "🎮"
    ]

    static let allIcons: [String] = {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ value: String) {
            guard !value.isEmpty, seen.insert(value).inserted else { return }
            result.append(value)
        }

        featuredIcons.forEach(append)

        let ranges: [ClosedRange<Int>] = [
            0x2600...0x27BF,
            0x1F300...0x1F5FF,
            0x1F600...0x1F64F,
            0x1F680...0x1F6FF,
            0x1F700...0x1F77F,
            0x1F780...0x1F7FF,
            0x1F800...0x1F8FF,
            0x1F900...0x1F9FF,
            0x1FA70...0x1FAFF
        ]

        for range in ranges {
            for value in range {
                guard let scalar = UnicodeScalar(value) else { continue }
                let properties = scalar.properties
                guard properties.isEmoji else { continue }
                guard properties.isEmojiPresentation || range.contains(value) else { continue }
                let character = String(Character(scalar))
                append(character)
            }
        }

        return result
    }()
}

struct ProfileIconPicker: View {
    @Binding var selectedIcon: String
    @State private var customEmoji = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Emoji personnalisé", text: $customEmoji)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: customEmoji) { _, newValue in
                    guard let emoji = firstEmoji(in: newValue) else { return }
                    selectedIcon = emoji
                    customEmoji = emoji
                }

            Text("Tu peux choisir dans la liste ou saisir n'importe quel emoji avec le clavier emoji iOS.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ProfileIconLibrary.allIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            customEmoji = icon
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Text(icon)
                                    .font(.system(size: 28))
                            }
                            .overlay(
                                Circle()
                                    .stroke(selectedIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Icône \(icon)")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 260, maxHeight: 420)
            .onAppear {
                if customEmoji.isEmpty {
                    customEmoji = selectedIcon
                }
            }
        }
    }

    private func firstEmoji(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for character in trimmed {
            if character.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
                return String(character)
            }
        }
        return nil
    }
}

struct EmojiAvatarView: View {
    let profileIcon: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))
            Text(profileIcon)
                .font(.system(size: size * 0.48))
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 1))
    }
}


struct ProfileAvatarImageView: View {
    let imageData: Data?
    let photoURL: String?
    let fallbackSymbol: String
    let size: CGFloat

    var body: some View {
        Group {
            if let imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let photoURL,
                      let url = URL(string: photoURL),
                      !photoURL.isEmpty {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct ProfilePhotoPicker: View {
    @Binding var selectedImageData: Data?
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(selectedImageData == nil ? "Choisir une photo" : "Remplacer la photo", systemImage: "photo")
            }
            .buttonStyle(.borderedProminent)

            if selectedImageData != nil {
                Button(role: .destructive) {
                    selectedItem = nil
                    selectedImageData = nil
                } label: {
                    Label("Retirer la photo sélectionnée", systemImage: "trash")
                }
            }

            Text("Formats recommandés : JPG ou PNG. La photo est envoyée dans Firebase Storage puis enregistrée dans le champ photoUrl du profil.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: selectedItem) {
            guard let selectedItem else { return }
            do {
                if let data = try await selectedItem.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
            } catch {
                selectedImageData = nil
            }
        }
    }
}
