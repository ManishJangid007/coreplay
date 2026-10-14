import Foundation

/// A title: one of a DVD's or Blu-ray's films, episodes, extras or menus,
/// as in VLC's Title menu. Matroska editions are titles too.
public struct MediaTitle: Identifiable, Hashable, Sendable {
    /// The engine's index for the title.
    public var id: Int
    /// The disc's own name for it, which most DVDs don't have.
    public var name: String?
    public var duration: TimeInterval
    /// A menu: a DVD's menus, a Blu-ray's top menu.
    public var isMenu: Bool
    /// The disc takes the arrows and Select while it plays.
    public var isInteractive: Bool
    public var chapterCount: Int

    public init(
        id: Int,
        name: String? = nil,
        duration: TimeInterval = 0,
        isMenu: Bool = false,
        isInteractive: Bool = false,
        chapterCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.isMenu = isMenu
        self.isInteractive = isInteractive
        self.chapterCount = chapterCount
    }

    /// The disc's own name for it, or "Title 3". Menus are "Menu" when the
    /// disc doesn't name them.
    /// - Parameter number: Its place among the titles that aren't menus, from 1.
    public func displayName(number: Int) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return isMenu ? "Menu" : "Title \(number)"
    }

    /// "1:52:04 · 24 chapters", or `nil` when there's nothing to say.
    public var details: String? {
        var parts: [String] = []
        if duration >= 1 {
            parts.append(PlaybackTimeFormatter.string(from: duration))
        }
        if chapterCount > 1 {
            parts.append("\(chapterCount) chapters")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// The disc's film: its longest title that isn't a menu.
    public static func mainFeature(in titles: [MediaTitle]) -> MediaTitle? {
        titles.filter { !$0.isMenu }.max { $0.duration < $1.duration }
    }

    /// The titles to offer in a list, numbered as players number them:
    /// menus aren't counted.
    public static func numbered(_ titles: [MediaTitle]) -> [(number: Int, title: MediaTitle)] {
        var number = 0
        return titles.filter { !$0.isMenu }.map { title in
            number += 1
            return (number, title)
        }
    }

    /// `true` when there's a choice of titles worth showing: more than one
    /// that isn't a menu.
    public static func offersChoice(_ titles: [MediaTitle]) -> Bool {
        titles.count(where: { !$0.isMenu }) > 1
    }
}

/// Moving around a disc's menu, as with a DVD player's remote.
public enum DiscNavigation: String, Hashable, Sendable, CaseIterable {
    case up
    case down
    case left
    case right
    /// Presses the highlighted button.
    case activate
    /// A DVD's main menu, or a Blu-ray's top menu.
    case menu
    /// A Blu-ray's pop-up menu, over the film.
    case popUpMenu

    public var title: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .activate: "Select"
        case .menu: "Menu"
        case .popUpMenu: "Pop-Up Menu"
        }
    }
}
