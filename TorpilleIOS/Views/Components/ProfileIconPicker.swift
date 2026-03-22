import SwiftUI

struct ProfileIconLibrary {
    static let icons = [
        "🍺", "🍻", "🎯", "🚀", "⚡️", "🔥", "🌊", "⭐️",
        "🦈", "🐬", "🦊", "🐻", "🐼", "🐯", "🦁", "🐸",
        "🐵", "🦄", "🐙", "🦉", "🍀", "🌈", "🍕", "🎮"
    ]
}

struct ProfileIconPicker: View {
    @Binding var selectedIcon: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ProfileIconLibrary.icons, id: \.self) { icon in
                Button {
                    selectedIcon = icon
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
