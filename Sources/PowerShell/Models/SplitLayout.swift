import Foundation

enum SplitLayout: Equatable {
    case horizontal(left: UUID, right: UUID)
    case vertical(top: UUID, bottom: UUID)
    case grid(topLeft: UUID, topRight: UUID, bottomLeft: UUID, bottomRight: UUID)

    var sessionIds: [UUID] {
        switch self {
        case .horizontal(let l, let r): return [l, r]
        case .vertical(let t, let b): return [t, b]
        case .grid(let tl, let tr, let bl, let br): return [tl, tr, bl, br]
        }
    }

    func contains(_ id: UUID) -> Bool { sessionIds.contains(id) }
}
