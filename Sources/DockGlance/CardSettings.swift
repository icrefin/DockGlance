import Foundation
import Observation

/// Which side of the screen a card sits on.
enum CardSide: String, CaseIterable {
    case left
    case right
}

/// Per-card visibility, display order and side, persisted in `UserDefaults`.
/// All cards are visible, sit on the left and follow the canonical order by
/// default.
@MainActor
@Observable
final class CardSettings {
    private static let storageKey = "cardVisibility"
    private static let orderKey = "cardOrder"
    private static let sideKey = "cardSide"

    private var visibility: [String: Bool]
    private(set) var order: [CardKind]
    private var sideRaw: [String: String]

    init() {
        let defaults = UserDefaults.standard
        visibility = defaults.dictionary(forKey: Self.storageKey)
            as? [String: Bool] ?? [:]
        if let stored = defaults.array(forKey: Self.orderKey) as? [String] {
            let known = stored.compactMap { CardKind(rawValue: $0) }
            let missing = CardKind.allCases.filter { !known.contains($0) }
            order = known + missing
        } else {
            order = CardKind.allCases
        }
        sideRaw = defaults.dictionary(forKey: Self.sideKey) as? [String: String] ?? [:]
    }

    func isVisible(_ kind: CardKind) -> Bool {
        visibility[kind.rawValue] ?? true
    }

    func setVisible(_ visible: Bool, for kind: CardKind) {
        visibility[kind.rawValue] = visible
        persist()
    }

    func setAllVisible(_ visible: Bool) {
        visibility = [:]
        if visible {
            for kind in CardKind.allCases { visibility[kind.rawValue] = true }
        }
        persist()
    }

func side(of kind: CardKind) -> CardSide {
    if let raw = sideRaw[kind.rawValue], let side = CardSide(rawValue: raw) {
        return side
    }
    return .left
}

    func setSide(_ side: CardSide, for kind: CardKind) {
        sideRaw[kind.rawValue] = side.rawValue
        persist()
    }

    /// Sorts kinds into the user's chosen display order.
    func ordered(_ kinds: [CardKind]) -> [CardKind] {
        kinds.sorted { index(of: $0) < index(of: $1) }
    }

    private func index(of kind: CardKind) -> Int {
        order.firstIndex(of: kind) ?? 0
    }

    /// Moves a card one step in `direction` (-1 = earlier, +1 = later).
    func move(_ kind: CardKind, by direction: Int) {
        guard let from = order.firstIndex(of: kind) else { return }
        let to = min(max(from + direction, 0), order.count - 1)
        guard to != from else { return }
        order.swapAt(from, to)
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(visibility, forKey: Self.storageKey)
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
        defaults.set(sideRaw, forKey: Self.sideKey)
    }

    /// Captures the current layout for a profile.
    func snapshot() -> LayoutState {
        LayoutState(
            visibility: visibility,
            order: order.map(\.rawValue),
            side: sideRaw
        )
    }

    /// Restores a layout saved in a profile. Entries for card kinds that no
    /// longer exist are dropped and any new kinds are appended to the order,
    /// mirroring the merge in `init`.
    func restore(_ layout: LayoutState) {
        let known = Set(CardKind.allCases.map(\.rawValue))
        visibility = layout.visibility.filter { known.contains($0.key) }
        let stored = layout.order.compactMap { CardKind(rawValue: $0) }
        let missing = CardKind.allCases.filter { !stored.contains($0) }
        order = stored + missing
        sideRaw = layout.side.filter { known.contains($0.key) }
        persist()
    }
}