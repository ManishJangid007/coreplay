import Foundation
import PlaybackCore

/// The Up Next queue, with Apple Music's shuffle and repeat behaviour.
///
/// - Shuffle keeps the current item playing and shuffles only what's upcoming;
///   turning it off restores the original order.
/// - Repeat One replays the current item when it ends on its own, but Next
///   still moves on.
/// - Repeat All wraps from the last item back to the first.
///
/// Pure value type: no engines, no system APIs, fully unit tested.
public struct PlaybackQueue: Hashable, Sendable {
    public enum RepeatMode: String, Hashable, Sendable, CaseIterable {
        case off
        case all
        case one

        /// The mode a repeat button cycles to next.
        public var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    /// Items in play order (shuffled order while shuffle is on).
    public private(set) var items: [PlaybackItem] = []
    public private(set) var currentIndex: Int?
    /// Items that finished or were skipped, oldest first.
    public private(set) var history: [PlaybackItem] = []
    public var repeatMode: RepeatMode = .off
    public private(set) var isShuffled = false
    /// Original order of item IDs, used to undo shuffle.
    private var originalOrder: [PlaybackItem.ID] = []

    /// Maximum number of history entries kept.
    public static let historyLimit = 200

    public init() {}

    // MARK: Reading

    public var currentItem: PlaybackItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    public var upNext: [PlaybackItem] {
        guard let currentIndex else { return items }
        return Array(items.dropFirst(currentIndex + 1))
    }

    public var isEmpty: Bool { items.isEmpty }

    public var hasNext: Bool {
        guard let currentIndex else { return !items.isEmpty }
        return currentIndex + 1 < items.count || (repeatMode == .all && !items.isEmpty)
    }

    public var hasPrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0 || (repeatMode == .all && items.count > 1)
    }

    // MARK: Replacing

    /// Replaces the queue and makes `items[index]` current.
    public mutating func replace(with newItems: [PlaybackItem], startingAt index: Int = 0) {
        var generator = SystemRandomNumberGenerator()
        replace(with: newItems, startingAt: index, using: &generator)
    }

    public mutating func replace(with newItems: [PlaybackItem], startingAt index: Int = 0, using generator: inout some RandomNumberGenerator) {
        if let current = currentItem {
            appendToHistory(current)
        }
        items = newItems
        originalOrder = newItems.map(\.id)
        currentIndex = newItems.isEmpty ? nil : min(max(index, 0), newItems.count - 1)
        if isShuffled {
            shuffleUpcoming(using: &generator)
        }
    }

    public mutating func clear() {
        items = []
        originalOrder = []
        currentIndex = nil
    }

    // MARK: Adding

    /// Inserts items right after the current one ("Play Next").
    public mutating func playNext(_ newItems: [PlaybackItem]) {
        guard !newItems.isEmpty else { return }
        let insertionIndex = (currentIndex ?? -1) + 1
        items.insert(contentsOf: newItems, at: insertionIndex)
        if let current = currentItem, let originalIndex = originalOrder.firstIndex(of: current.id) {
            originalOrder.insert(contentsOf: newItems.map(\.id), at: originalIndex + 1)
        } else {
            originalOrder.insert(contentsOf: newItems.map(\.id), at: 0)
        }
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    /// Adds items to the end ("Play Later").
    public mutating func playLater(_ newItems: [PlaybackItem]) {
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        originalOrder.append(contentsOf: newItems.map(\.id))
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    // MARK: Moving through the queue

    /// Moves to the next item and returns it, or `nil` at the end of the queue.
    /// - Parameter automatic: `true` when the current item ended by itself
    ///   (Repeat One then replays it); `false` for the Next button.
    public mutating func advance(automatic: Bool) -> PlaybackItem? {
        guard let currentIndex, let current = currentItem else {
            if !items.isEmpty {
                self.currentIndex = 0
                return items[0]
            }
            return nil
        }
        if automatic, repeatMode == .one {
            return current
        }
        if currentIndex + 1 < items.count {
            appendToHistory(current)
            self.currentIndex = currentIndex + 1
            return items[currentIndex + 1]
        }
        if repeatMode == .all, !items.isEmpty {
            appendToHistory(current)
            self.currentIndex = 0
            return items[0]
        }
        return nil
    }

    /// Moves to the previous item and returns it, or `nil` at the start.
    public mutating func goBack() -> PlaybackItem? {
        guard let currentIndex else { return nil }
        if currentIndex > 0 {
            self.currentIndex = currentIndex - 1
            return items[currentIndex - 1]
        }
        if repeatMode == .all, items.count > 1 {
            self.currentIndex = items.count - 1
            return items[items.count - 1]
        }
        return nil
    }

    /// Makes the item with `id` current (tapping a row in Up Next).
    @discardableResult
    public mutating func jump(to id: PlaybackItem.ID) -> PlaybackItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        if let current = currentItem, current.id != id {
            appendToHistory(current)
        }
        currentIndex = index
        return items[index]
    }

    // MARK: Editing Up Next

    /// Removes an upcoming item. The current item can't be removed this way.
    public mutating func remove(id: PlaybackItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index != currentIndex else { return }
        items.remove(at: index)
        originalOrder.removeAll { $0 == id }
        if let currentIndex, index < currentIndex {
            self.currentIndex = currentIndex - 1
        }
    }

    /// Reorders Up Next. Offsets are positions within `upNext`, as a SwiftUI
    /// `onMove` handler provides them.
    public mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (currentIndex ?? -1) + 1
        var upcoming = Array(items[base...])
        let moving = source.sorted().filter { upcoming.indices.contains($0) }.map { upcoming[$0] }
        guard !moving.isEmpty else { return }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        for offset in source.sorted(by: >) where upcoming.indices.contains(offset) {
            upcoming.remove(at: offset)
        }
        let insertion = min(max(destination - removedBeforeDestination, 0), upcoming.count)
        upcoming.insert(contentsOf: moving, at: insertion)
        items.replaceSubrange(base..., with: upcoming)
    }

    // MARK: Shuffle

    public mutating func setShuffle(_ enabled: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffle(enabled, using: &generator)
    }

    public mutating func setShuffle(_ enabled: Bool, using generator: inout some RandomNumberGenerator) {
        guard enabled != isShuffled else { return }
        isShuffled = enabled
        if enabled {
            shuffleUpcoming(using: &generator)
        } else {
            restoreOriginalOrder()
        }
    }

    private mutating func shuffleUpcoming(using generator: inout some RandomNumberGenerator) {
        guard let currentIndex else {
            items.shuffle(using: &generator)
            return
        }
        // The current item moves to the front; everything else is shuffled after it.
        let current = items[currentIndex]
        var rest = items
        rest.remove(at: currentIndex)
        rest.shuffle(using: &generator)
        items = [current] + rest
        self.currentIndex = 0
    }

    private mutating func restoreOriginalOrder() {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var restored = originalOrder.compactMap { byID[$0] }
        // Anything not in the original order (shouldn't happen) goes last.
        let known = Set(originalOrder)
        restored += items.filter { !known.contains($0.id) }
        let currentID = currentItem?.id
        items = restored
        currentIndex = currentID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? (items.isEmpty ? nil : 0)
    }

    private mutating func appendToHistory(_ item: PlaybackItem) {
        history.append(item)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }
}
