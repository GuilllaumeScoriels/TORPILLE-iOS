import SwiftUI
import PhotosUI
import UIKit
import ImageIO

private actor ProfileAvatarImagePipeline {
    static let shared = ProfileAvatarImagePipeline()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    private var requests: [String: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let request = requests[key] { return await request.value }

        let request = Task<UIImage?, Never> {
            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: thumbnail)
        }
        requests[key] = request
        let image = await request.value
        requests[key] = nil
        if let image, let cgImage = image.cgImage {
            cache.setObject(image, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }
}

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
    @EnvironmentObject private var languageService: AppLanguageService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(languageService.phrase("Emoji personnalisé"), text: $customEmoji)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: customEmoji) { _, newValue in
                    guard let emoji = firstEmoji(in: newValue) else { return }
                    selectedIcon = emoji
                    customEmoji = emoji
                }

            Text(languageService.phrase("Tu peux choisir dans la liste ou saisir n'importe quel emoji avec le clavier emoji iOS."))
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
                        .accessibilityLabel(languageService.iconAccessibilityLabel(icon))
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
    var fallbackIcon: String? = nil
    @State private var remoteImage: UIImage?
    @State private var didFinishLoadingImage = false

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
                if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Group {
                        if didFinishLoadingImage { placeholder }
                        else { TorpilleLoadingView() }
                    }
                    .task(id: photoURL) {
                        remoteImage = await ProfileAvatarImagePipeline.shared.image(for: url)
                        didFinishLoadingImage = true
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 1))
        .onChange(of: photoURL) { _, _ in
            remoteImage = nil
            didFinishLoadingImage = false
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))
            if let fallbackIcon, !fallbackIcon.isEmpty {
                Text(fallbackIcon)
                    .font(.system(size: size * 0.48))
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfilePhotoPicker: View {
    @Binding var selectedImageData: Data?
    @State private var selectedItem: PhotosPickerItem?
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        let photoPickerTitle = languageService.phrase(selectedImageData == nil ? "Choisir une photo" : "Remplacer la photo")

        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(photoPickerTitle, systemImage: "photo")
            }
            .buttonStyle(.borderedProminent)

            if selectedImageData != nil {
                Button(role: .destructive) {
                    selectedItem = nil
                    selectedImageData = nil
                } label: {
                    Label(languageService.phrase("Retirer la photo sélectionnée"), systemImage: "trash")
                }
            }

            Text(languageService.phrase("Formats recommandés : JPG ou PNG."))
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

struct ProfileSexPicker: View {
    @Binding var selection: ProfileSex?
    @EnvironmentObject private var languageService: AppLanguageService

    var body: some View {
        Picker(languageService.phrase("Sexe"), selection: $selection) {
            Text(languageService.phrase("Non renseigné")).tag(nil as ProfileSex?)
            ForEach(ProfileSex.allCases) { value in
                Text(languageService.phrase(value.label)).tag(Optional(value))
            }
        }
        .pickerStyle(.menu)
    }
}
