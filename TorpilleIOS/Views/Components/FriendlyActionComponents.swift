import SwiftUI

private let bannerRed = Color(red: 0.83, green: 0.10, blue: 0.16)

enum ActionAccent {
    case ocean
    case sunset
    case meadow
    case berry
    case gold
    case violet
    case coral
    case slate

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var colors: [Color] {
        switch self {
        case .ocean:
            return [Color(red: 0.16, green: 0.53, blue: 0.96), Color(red: 0.14, green: 0.78, blue: 0.78)]
        case .sunset:
            return [Color(red: 0.99, green: 0.47, blue: 0.38), Color(red: 0.98, green: 0.72, blue: 0.28)]
        case .meadow:
            return [Color(red: 0.24, green: 0.72, blue: 0.48), Color(red: 0.50, green: 0.84, blue: 0.36)]
        case .berry:
            return [Color(red: 0.78, green: 0.26, blue: 0.63), Color(red: 0.97, green: 0.40, blue: 0.59)]
        case .gold:
            return [Color(red: 0.96, green: 0.66, blue: 0.14), Color(red: 0.98, green: 0.82, blue: 0.29)]
        case .violet:
            return [Color(red: 0.42, green: 0.42, blue: 0.92), Color(red: 0.71, green: 0.47, blue: 0.95)]
        case .coral:
            return [Color(red: 0.98, green: 0.40, blue: 0.48), Color(red: 0.99, green: 0.58, blue: 0.43)]
        case .slate:
            return [Color(red: 0.25, green: 0.33, blue: 0.47), Color(red: 0.42, green: 0.52, blue: 0.67)]
        }
    }

    var tint: Color {
        colors.first ?? .accentColor
    }
}

struct WelcomeHeroCard: View {
    let title: String
    let subtitle: String
    let primarySymbol: String
    let secondarySymbol: String
    let cornerSymbol: String
    let accent: ActionAccent

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            heroBadge
                .fixedSize()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerRed)
        .overlay(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .padding(10)
                .allowsHitTesting(false)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 30, bottomTrailingRadius: 24, topTrailingRadius: 44, style: .continuous))
        .shadow(color: bannerRed.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private var heroBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: 108, height: 108)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                        .padding(8)
                }

            Image(systemName: secondarySymbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: 8, y: -10)

            Image(systemName: primarySymbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 58, height: 58)
                .background(.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .offset(x: -10, y: 12)

            Image(systemName: cornerSymbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .offset(x: 30, y: -30)
        }
        .accessibilityHidden(true)
    }
}

struct IllustratedActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let illustrationSymbol: String
    let accent: ActionAccent
    var trailingText: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.20))
                    .frame(width: 70, height: 70)
                Image(systemName: illustrationSymbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.35))
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.22))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 10)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
         .background(accent.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: accent.tint.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

struct CompactActionButton: View {
    let title: String
    let systemImage: String
    let accent: ActionAccent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
         .background(accent.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: accent.tint.opacity(0.16), radius: 10, x: 0, y: 6)
    }
}

struct SectionTitleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct MainTabScreenSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 14)
            }
    }
}

extension View {
    func reserveMainTabBarSpace() -> some View {
        modifier(MainTabScreenSpacingModifier())
    }
}
