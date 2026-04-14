import AppKit
import Foundation

struct DeviceSpec {
    let name: String
    let size: CGSize
    let cornerRadius: CGFloat
    let topInset: CGFloat
    let sideInset: CGFloat
    let bottomInset: CGFloat
    let tabBarHeight: CGFloat
    let statusScale: CGFloat
}

struct Palette {
    static let background = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1)
    static let card = NSColor.white
    static let line = NSColor(calibratedWhite: 0.88, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.10, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.42, alpha: 1)
    static let tab = NSColor(calibratedWhite: 0.55, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.12, green: 0.48, blue: 1.0, alpha: 1)
    static let green = NSColor(calibratedRed: 0.19, green: 0.79, blue: 0.47, alpha: 1)
    static let teal = NSColor(calibratedRed: 0.18, green: 0.79, blue: 0.85, alpha: 1)
    static let orange = NSColor(calibratedRed: 1.0, green: 0.71, blue: 0.22, alpha: 1)
    static let pink = NSColor(calibratedRed: 1.0, green: 0.49, blue: 0.60, alpha: 1)
    static let purple = NSColor(calibratedRed: 0.53, green: 0.44, blue: 0.96, alpha: 1)
    static let unread = NSColor(calibratedRed: 0.93, green: 0.96, blue: 1.0, alpha: 1)
    static let mapWater = NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 1)
    static let mapPark = NSColor(calibratedRed: 0.84, green: 0.95, blue: 0.84, alpha: 1)
    static let mapLand = NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.90, alpha: 1)
}

let iphone = DeviceSpec(
    name: "iphone",
    size: CGSize(width: 1290, height: 2796),
    cornerRadius: 56,
    topInset: 86,
    sideInset: 54,
    bottomInset: 34,
    tabBarHeight: 146,
    statusScale: 1
)

let ipad = DeviceSpec(
    name: "ipad",
    size: CGSize(width: 2048, height: 2732),
    cornerRadius: 40,
    topInset: 74,
    sideInset: 74,
    bottomInset: 28,
    tabBarHeight: 0,
    statusScale: 1.12
)

let outputDirectory = URL(fileURLWithPath: "/Users/sixtinedetournay/Downloads/TorpilleIOS_v56_2/MarketingShots", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makeImage(size: CGSize, draw: () -> Void) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "export", code: 1)
    }
    try data.write(to: url)
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawGradientRect(_ rect: CGRect, radius: CGFloat, colors: [NSColor], angle: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    NSGradient(colors: colors)?.draw(in: rect, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

func textStyle(_ size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Palette.text) -> [NSAttributedString.Key: Any] {
    [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ]
}

func drawText(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Palette.text, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: string).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
}

func drawSymbol(_ name: String, in rect: CGRect, color: NSColor = .white, weight: NSFont.Weight = .regular) {
    let config = NSImage.SymbolConfiguration(pointSize: min(rect.width, rect.height) * 0.7, weight: weight)
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    let tinted = image.copy() as! NSImage
    tinted.lockFocus()
    color.set()
    NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: rect)
}

func drawAvatar(center: CGPoint, radius: CGFloat, name: String, gradient: [NSColor]) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSGraphicsContext.saveGraphicsState()
    let path = NSBezierPath(ovalIn: rect)
    path.addClip()
    NSGradient(colors: gradient)?.draw(in: rect, angle: 45)
    NSGraphicsContext.restoreGraphicsState()

    let headRect = CGRect(x: rect.midX - radius * 0.33, y: rect.midY + radius * 0.05, width: radius * 0.66, height: radius * 0.66)
    NSColor(calibratedWhite: 1, alpha: 0.72).setFill()
    NSBezierPath(ovalIn: headRect).fill()

    let shoulderRect = CGRect(x: rect.midX - radius * 0.62, y: rect.minY + radius * 0.20, width: radius * 1.24, height: radius * 0.82)
    let shoulder = NSBezierPath(roundedRect: shoulderRect, xRadius: radius * 0.42, yRadius: radius * 0.42)
    shoulder.fill()

    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
    NSColor.white.withAlphaComponent(0.42).setStroke()
    ring.lineWidth = 4
    ring.stroke()

    let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    drawText(initials, in: CGRect(x: rect.minX, y: rect.midY - radius * 0.2, width: rect.width, height: radius * 0.4), size: radius * 0.42, weight: .heavy, color: .white.withAlphaComponent(0.95), alignment: .center)
}

func drawStatusBar(spec: DeviceSpec, time: String) {
    let y = spec.size.height - spec.topInset + 8
    drawText(time, in: CGRect(x: spec.sideInset, y: y, width: 120, height: 40), size: 34 * spec.statusScale, weight: .semibold)

    let rightX = spec.size.width - spec.sideInset - 160
    drawSymbol("cellularbars", in: CGRect(x: rightX, y: y + 2, width: 34, height: 24), color: Palette.text, weight: .semibold)
    drawSymbol("wifi", in: CGRect(x: rightX + 44, y: y + 1, width: 30, height: 24), color: Palette.text, weight: .semibold)

    let batteryRect = CGRect(x: rightX + 88, y: y + 3, width: 54, height: 22)
    let outer = NSBezierPath(roundedRect: batteryRect, xRadius: 6, yRadius: 6)
    Palette.text.setStroke()
    outer.lineWidth = 2
    outer.stroke()
    NSBezierPath(rect: CGRect(x: batteryRect.maxX + 3, y: batteryRect.midY - 4, width: 3, height: 8)).fill()
    drawRoundedRect(CGRect(x: batteryRect.minX + 3, y: batteryRect.minY + 3, width: 34, height: batteryRect.height - 6), radius: 4, fill: Palette.green)
}

func drawTabBar(spec: DeviceSpec, selected: Int) {
    guard spec.tabBarHeight > 0 else { return }
    let rect = CGRect(x: 0, y: 0, width: spec.size.width, height: spec.tabBarHeight + spec.bottomInset)
    drawRoundedRect(rect, radius: 0, fill: NSColor.white.withAlphaComponent(0.95), stroke: Palette.line)

    let titles = ["Home", "Communities", "Profile", "Leaderboard", "Map"]
    let symbols = ["house.fill", "person.3.fill", "person.fill", "trophy.fill", "map.fill"]
    let itemWidth = spec.size.width / CGFloat(titles.count)

    for (index, title) in titles.enumerated() {
        let color = index == selected ? Palette.blue : Palette.tab
        let x = CGFloat(index) * itemWidth
        drawSymbol(symbols[index], in: CGRect(x: x + itemWidth / 2 - 18, y: 62, width: 36, height: 30), color: color, weight: .semibold)
        drawText(title, in: CGRect(x: x + 8, y: 24, width: itemWidth - 16, height: 24), size: 22, weight: index == selected ? .semibold : .medium, color: color, alignment: .center)
    }

    drawRoundedRect(CGRect(x: spec.size.width / 2 - 112, y: 8, width: 224, height: 8), radius: 4, fill: NSColor.black.withAlphaComponent(0.88))
}

func drawTopHeader(title: String, subtitle: String?, leftSymbol: String?, rightSymbols: [String], yTop: CGFloat, width: CGFloat, sideInset: CGFloat) {
    if let leftSymbol {
        drawSymbol(leftSymbol, in: CGRect(x: sideInset, y: yTop - 8, width: 34, height: 34), color: Palette.text, weight: .semibold)
    }
    drawText(title, in: CGRect(x: sideInset + (leftSymbol == nil ? 0 : 50), y: yTop - 6, width: width - sideInset * 2 - 180, height: 38), size: 36, weight: .bold)
    if let subtitle {
        drawText(subtitle, in: CGRect(x: sideInset + (leftSymbol == nil ? 0 : 50), y: yTop - 34, width: width - sideInset * 2 - 180, height: 26), size: 20, weight: .regular, color: Palette.muted)
    }
    for (offset, symbol) in rightSymbols.enumerated() {
        drawSymbol(symbol, in: CGRect(x: width - sideInset - CGFloat(offset + 1) * 44, y: yTop - 8, width: 30, height: 30), color: Palette.text, weight: .semibold)
    }
}

func makeHomeShot() throws {
    let spec = iphone
    let image = makeImage(size: spec.size) {
        Palette.background.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: spec.size)).fill()
        drawStatusBar(spec: spec, time: "9:41")
        drawTopHeader(title: "Home", subtitle: "Welcome back, Maya", leftSymbol: nil, rightSymbols: ["bell.fill", "play.rectangle.fill"], yTop: spec.size.height - 150, width: spec.size.width, sideInset: spec.sideInset)

        let profileRect = CGRect(x: spec.sideInset, y: spec.size.height - 390, width: spec.size.width - spec.sideInset * 2, height: 180)
        drawGradientRect(profileRect, radius: 34, colors: [NSColor(calibratedRed: 0.17, green: 0.54, blue: 1.0, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.77, alpha: 1)], angle: 0)
        drawAvatar(center: CGPoint(x: profileRect.minX + 90, y: profileRect.midY), radius: 50, name: "Maya Ross", gradient: [Palette.purple, Palette.blue])
        drawText("Maya Ross", in: CGRect(x: profileRect.minX + 170, y: profileRect.midY + 16, width: 320, height: 38), size: 36, weight: .bold, color: .white)
        drawText("Total XP · 12,840", in: CGRect(x: profileRect.minX + 170, y: profileRect.midY - 22, width: 300, height: 28), size: 22, weight: .semibold, color: .white.withAlphaComponent(0.88))
        drawRoundedRect(CGRect(x: profileRect.maxX - 170, y: profileRect.midY - 30, width: 120, height: 60), radius: 24, fill: .white.withAlphaComponent(0.18))
        drawText("Profile", in: CGRect(x: profileRect.maxX - 170, y: profileRect.midY - 12, width: 120, height: 24), size: 22, weight: .semibold, color: .white, alignment: .center)

        drawText("Quick actions", in: CGRect(x: spec.sideInset, y: spec.size.height - 470, width: 260, height: 34), size: 28, weight: .bold)
        let actionY = spec.size.height - 680
        let actionHeight: CGFloat = 156
        let gap: CGFloat = 22
        let actionWidth = (spec.size.width - spec.sideInset * 2 - gap) / 2
        let actions = [
            ("Create community", "plus.bubble.fill", [Palette.orange, NSColor(calibratedRed: 1, green: 0.83, blue: 0.36, alpha: 1)]),
            ("Global leaderboard", "trophy.fill", [Palette.blue, Palette.teal])
        ]
        for (index, action) in actions.enumerated() {
            let rect = CGRect(x: spec.sideInset + CGFloat(index) * (actionWidth + gap), y: actionY, width: actionWidth, height: actionHeight)
            drawGradientRect(rect, radius: 30, colors: action.2, angle: 0)
            drawRoundedRect(CGRect(x: rect.minX + 24, y: rect.midY - 28, width: 56, height: 56), radius: 18, fill: .white.withAlphaComponent(0.16))
            drawSymbol(action.1, in: CGRect(x: rect.minX + 34, y: rect.midY - 18, width: 36, height: 36), color: .white, weight: .semibold)
            drawText(action.0, in: CGRect(x: rect.minX + 96, y: rect.midY - 12, width: rect.width - 120, height: 54), size: 28, weight: .bold, color: .white)
        }

        drawText("Your communities", in: CGRect(x: spec.sideInset, y: spec.size.height - 760, width: 300, height: 34), size: 28, weight: .bold)
        let communities = [
            ("Harbor Crew", "Private · Reply in 45s", [Palette.green, Palette.teal], "7 active"),
            ("Sunset Riders", "Public · Reply in 60s", [Palette.pink, NSColor(calibratedRed: 1, green: 0.70, blue: 0.42, alpha: 1)], "14 active"),
            ("Night Shift", "Private · Reply in 30s", [Palette.purple, NSColor(calibratedRed: 0.30, green: 0.36, blue: 0.89, alpha: 1)], "3 new")
        ]
        for (index, community) in communities.enumerated() {
            let rect = CGRect(x: spec.sideInset, y: spec.size.height - 970 - CGFloat(index) * 178, width: spec.size.width - spec.sideInset * 2, height: 150)
            drawRoundedRect(rect, radius: 28, fill: Palette.card, stroke: Palette.line)
            let accent = CGRect(x: rect.minX + 18, y: rect.minY + 18, width: 124, height: rect.height - 36)
            drawGradientRect(accent, radius: 22, colors: community.2, angle: 0)
            drawSymbol("bubble.left.and.bubble.right.fill", in: CGRect(x: accent.midX - 24, y: accent.midY - 24, width: 48, height: 48), color: .white, weight: .regular)
            drawText(community.0, in: CGRect(x: rect.minX + 166, y: rect.midY + 20, width: 420, height: 32), size: 30, weight: .bold)
            drawText(community.1, in: CGRect(x: rect.minX + 166, y: rect.midY - 16, width: 360, height: 26), size: 22, weight: .medium, color: Palette.muted)
            drawRoundedRect(CGRect(x: rect.maxX - 150, y: rect.midY - 22, width: 112, height: 44), radius: 18, fill: Palette.unread)
            drawText(community.3, in: CGRect(x: rect.maxX - 150, y: rect.midY - 10, width: 112, height: 20), size: 18, weight: .bold, color: Palette.blue, alignment: .center)
        }

        drawTabBar(spec: spec, selected: 0)
    }
    try writePNG(image, to: outputDirectory.appendingPathComponent("torpille-home-iphone-english.png"))
}

func bubbleRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fromMe: Bool, unread: Bool) {
    let fill = fromMe
        ? NSColor(calibratedRed: 0.16, green: 0.48, blue: 1.0, alpha: 1)
        : (unread ? Palette.unread : NSColor.white)
    drawRoundedRect(CGRect(x: x, y: y, width: width, height: height), radius: 28, fill: fill, stroke: fromMe ? nil : Palette.line)
}

func makeChatShot() throws {
    let spec = iphone
    let image = makeImage(size: spec.size) {
        Palette.background.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: spec.size)).fill()
        drawStatusBar(spec: spec, time: "10:28")
        drawTopHeader(title: "Harbor Crew", subtitle: "18 members · 5 online", leftSymbol: "chevron.left", rightSymbols: ["info.circle.fill"], yTop: spec.size.height - 150, width: spec.size.width, sideInset: spec.sideInset)

        let messagesTop = spec.size.height - 240
        let leftX = spec.sideInset
        let rightX = spec.size.width - spec.sideInset

        drawAvatar(center: CGPoint(x: leftX + 34, y: messagesTop - 24), radius: 24, name: "Theo Blake", gradient: [Palette.orange, Palette.pink])
        bubbleRect(x: leftX + 72, y: messagesTop - 78, width: 620, height: 104, fromMe: false, unread: false)
        drawText("Theo Blake", in: CGRect(x: leftX + 108, y: messagesTop - 28, width: 200, height: 24), size: 20, weight: .bold, color: Palette.blue)
        drawText("Anyone up for a sunset torpille round tonight?", in: CGRect(x: leftX + 108, y: messagesTop - 62, width: 540, height: 42), size: 24, weight: .medium)

        bubbleRect(x: rightX - 510, y: messagesTop - 226, width: 510, height: 122, fromMe: true, unread: false)
        drawText("I'm in. Dropping mine from the marina in 15.", in: CGRect(x: rightX - 470, y: messagesTop - 188, width: 430, height: 56), size: 24, weight: .semibold, color: .white)

        drawAvatar(center: CGPoint(x: leftX + 34, y: messagesTop - 300), radius: 24, name: "Lina Park", gradient: [Palette.green, Palette.teal])
        let mediaRect = CGRect(x: leftX + 72, y: messagesTop - 430, width: 680, height: 190)
        bubbleRect(x: mediaRect.minX, y: mediaRect.minY, width: mediaRect.width, height: mediaRect.height, fromMe: false, unread: true)
        drawGradientRect(CGRect(x: mediaRect.minX + 16, y: mediaRect.minY + 16, width: 210, height: 158), radius: 22, colors: [Palette.purple, Palette.blue], angle: 25)
        drawSymbol("video.fill", in: CGRect(x: mediaRect.minX + 88, y: mediaRect.minY + 66, width: 52, height: 52), color: .white, weight: .regular)
        drawText("Lina Park", in: CGRect(x: mediaRect.minX + 252, y: mediaRect.maxY - 52, width: 180, height: 24), size: 20, weight: .bold, color: Palette.blue)
        drawText("Video for @Maya", in: CGRect(x: mediaRect.minX + 252, y: mediaRect.maxY - 88, width: 220, height: 24), size: 22, weight: .bold)
        drawText("Saved in thread · 1m ago", in: CGRect(x: mediaRect.minX + 252, y: mediaRect.minY + 42, width: 260, height: 22), size: 18, weight: .semibold, color: Palette.muted)
        drawRoundedRect(CGRect(x: mediaRect.maxX - 144, y: mediaRect.minY + 62, width: 110, height: 44), radius: 18, fill: Palette.blue)
        drawText("Play", in: CGRect(x: mediaRect.maxX - 144, y: mediaRect.minY + 74, width: 110, height: 20), size: 18, weight: .bold, color: .white, alignment: .center)

        drawAvatar(center: CGPoint(x: leftX + 34, y: messagesTop - 504), radius: 24, name: "Jasper Cole", gradient: [Palette.blue, Palette.teal])
        bubbleRect(x: leftX + 72, y: messagesTop - 560, width: 600, height: 98, fromMe: false, unread: true)
        drawText("Jasper Cole", in: CGRect(x: leftX + 108, y: messagesTop - 520, width: 220, height: 24), size: 20, weight: .bold, color: Palette.blue)
        drawText("That shot is unreal. Posting mine next.", in: CGRect(x: leftX + 108, y: messagesTop - 552, width: 520, height: 34), size: 24, weight: .medium)

        drawRoundedRect(CGRect(x: spec.sideInset, y: 186, width: spec.size.width - spec.sideInset * 2, height: 102), radius: 30, fill: .white, stroke: Palette.line)
        drawRoundedRect(CGRect(x: spec.sideInset + 18, y: 204, width: 66, height: 66), radius: 22, fill: Palette.unread)
        drawSymbol("plus", in: CGRect(x: spec.sideInset + 34, y: 222, width: 34, height: 34), color: Palette.blue, weight: .heavy)
        drawText("Write a message…", in: CGRect(x: spec.sideInset + 108, y: 220, width: 420, height: 28), size: 24, weight: .medium, color: Palette.muted)
        drawRoundedRect(CGRect(x: spec.size.width - spec.sideInset - 84, y: 204, width: 66, height: 66), radius: 22, fill: Palette.blue)
        drawSymbol("arrow.up", in: CGRect(x: spec.size.width - spec.sideInset - 64, y: 224, width: 26, height: 26), color: .white, weight: .bold)

        drawTabBar(spec: spec, selected: 1)
    }
    try writePNG(image, to: outputDirectory.appendingPathComponent("torpille-chat-iphone-english.png"))
}

func drawMapPin(at point: CGPoint, color: NSColor, name: String) {
    let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
    drawRoundedRect(rect, radius: 22, fill: color)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)).fill()
    drawText(name, in: CGRect(x: point.x - 90, y: point.y + 26, width: 180, height: 22), size: 16, weight: .bold, color: Palette.text, alignment: .center)
}

func makeMapShot() throws {
    let spec = ipad
    let image = makeImage(size: spec.size) {
        Palette.background.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: spec.size)).fill()
        drawStatusBar(spec: spec, time: "11:07")
        drawTopHeader(title: "Map", subtitle: "All shared communities", leftSymbol: nil, rightSymbols: ["line.3.horizontal.decrease.circle.fill"], yTop: spec.size.height - 132, width: spec.size.width, sideInset: spec.sideInset)

        let mapRect = CGRect(x: spec.sideInset, y: 120, width: spec.size.width - spec.sideInset * 2, height: spec.size.height - 250)
        drawRoundedRect(mapRect, radius: 34, fill: Palette.mapLand, stroke: Palette.line)

        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: mapRect, xRadius: 34, yRadius: 34)
        clip.addClip()
        Palette.mapWater.setFill()
        NSBezierPath(roundedRect: CGRect(x: mapRect.minX - 60, y: mapRect.minY + 170, width: 720, height: 320), xRadius: 130, yRadius: 130).fill()
        Palette.mapPark.setFill()
        NSBezierPath(roundedRect: CGRect(x: mapRect.minX + 1150, y: mapRect.minY + 300, width: 420, height: 280), xRadius: 90, yRadius: 90).fill()
        NSBezierPath(roundedRect: CGRect(x: mapRect.minX + 420, y: mapRect.minY + 840, width: 520, height: 250), xRadius: 84, yRadius: 84).fill()

        Palette.line.setStroke()
        for road in stride(from: mapRect.minY + 90, through: mapRect.maxY - 110, by: 180) {
            let roadPath = NSBezierPath()
            roadPath.move(to: CGPoint(x: mapRect.minX + 20, y: road))
            roadPath.curve(to: CGPoint(x: mapRect.maxX - 30, y: road + 36), controlPoint1: CGPoint(x: mapRect.minX + 360, y: road + 40), controlPoint2: CGPoint(x: mapRect.minX + 1020, y: road - 40))
            roadPath.lineWidth = 18
            roadPath.stroke()
        }
        for road in stride(from: mapRect.minX + 140, through: mapRect.maxX - 160, by: 220) {
            let roadPath = NSBezierPath()
            roadPath.move(to: CGPoint(x: road, y: mapRect.minY + 20))
            roadPath.curve(to: CGPoint(x: road + 40, y: mapRect.maxY - 30), controlPoint1: CGPoint(x: road - 30, y: mapRect.minY + 420), controlPoint2: CGPoint(x: road + 70, y: mapRect.minY + 1050))
            roadPath.lineWidth = 16
            roadPath.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        drawMapPin(at: CGPoint(x: mapRect.minX + 470, y: mapRect.minY + 970), color: Palette.blue, name: "Maya")
        drawMapPin(at: CGPoint(x: mapRect.minX + 720, y: mapRect.minY + 1220), color: Palette.orange, name: "Theo")
        drawMapPin(at: CGPoint(x: mapRect.minX + 1020, y: mapRect.minY + 820), color: Palette.green, name: "Lina")
        drawMapPin(at: CGPoint(x: mapRect.minX + 1340, y: mapRect.minY + 1040), color: Palette.pink, name: "Jasper")
        drawMapPin(at: CGPoint(x: mapRect.minX + 890, y: mapRect.minY + 510), color: Palette.purple, name: "Noah")
        drawMapPin(at: CGPoint(x: mapRect.minX + 1460, y: mapRect.minY + 640), color: Palette.teal, name: "Ava")

        let panel = CGRect(x: mapRect.maxX - 470, y: mapRect.maxY - 520, width: 390, height: 390)
        drawRoundedRect(panel, radius: 28, fill: NSColor.white.withAlphaComponent(0.96), stroke: Palette.line)
        drawText("Nearby torpilleurs", in: CGRect(x: panel.minX + 24, y: panel.maxY - 54, width: 240, height: 28), size: 26, weight: .bold)
        drawText("Shared communities · 6", in: CGRect(x: panel.minX + 24, y: panel.maxY - 84, width: 220, height: 22), size: 18, weight: .semibold, color: Palette.muted)

        let people: [(String, String, [NSColor])] = [
            ("Theo Blake", "Harbor Crew · 0.8 km", [Palette.orange, Palette.pink]),
            ("Lina Park", "Sunset Riders · 1.4 km", [Palette.green, Palette.teal]),
            ("Noah Reed", "Night Shift · 2.1 km", [Palette.purple, Palette.blue]),
            ("Ava Chen", "Harbor Crew · 2.7 km", [Palette.blue, Palette.teal])
        ]
        for (index, person) in people.enumerated() {
            let rowY = panel.maxY - 140 - CGFloat(index) * 74
            drawAvatar(center: CGPoint(x: panel.minX + 42, y: rowY), radius: 20, name: person.0, gradient: person.2)
            drawText(person.0, in: CGRect(x: panel.minX + 78, y: rowY + 6, width: 180, height: 22), size: 20, weight: .bold)
            drawText(person.1, in: CGRect(x: panel.minX + 78, y: rowY - 18, width: 220, height: 20), size: 16, weight: .medium, color: Palette.muted)
        }
    }
    try writePNG(image, to: outputDirectory.appendingPathComponent("torpille-map-ipad-english.png"))
}

do {
    try makeHomeShot()
    try makeChatShot()
    try makeMapShot()
    print("Generated screenshots in \(outputDirectory.path)")
} catch {
    fputs("Generation failed: \(error)\n", stderr)
    exit(1)
}
