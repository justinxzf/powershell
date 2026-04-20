import Foundation

@MainActor
final class FloatingNotificationCenter {
    struct Notification: Identifiable, Equatable {
        let id: UUID
        let title: String
        let body: String
        let sessionId: String
        var revealedInOverflow = false
    }

    enum Presentation: Equatable {
        case card(title: String, body: String, sessionId: String, footer: String?)
        case summary(hiddenCount: Int)
    }

    private var notifications: [Notification] = []

    @discardableResult
    func enqueue(title: String, body: String, sessionId: String) -> UUID {
        let notification = Notification(
            id: UUID(),
            title: title,
            body: body,
            sessionId: sessionId
        )
        notifications.append(notification)
        return notification.id
    }

    func dismiss(id: UUID) {
        let visibleIDs = Set(notifications.reversed().prefix(2).map(\.id))
        let removedVisibleCard = visibleIDs.contains(id)
        notifications.removeAll { $0.id == id }

        guard removedVisibleCard, notifications.count >= 3 else {
            return
        }

        let remaining = Array(notifications.reversed().dropFirst(2))
        let hasOverflowCard = remaining.contains { $0.revealedInOverflow }
        guard !hasOverflowCard else {
            return
        }

        revealNextHiddenNotification()
    }

    func advanceOverflow() {
        revealNextHiddenNotification()
    }

    func presentations() -> [Presentation] {
        let ordered = notifications.reversed()
        let visibleCards = Array(ordered.prefix(2))
        let overflowSource = Array(ordered.dropFirst(2))

        var presentations = visibleCards.map {
            Presentation.card(title: $0.title, body: $0.body, sessionId: $0.sessionId, footer: nil)
        }

        guard !overflowSource.isEmpty else {
            return presentations
        }

        let overflowRevealed = overflowSource.filter(\.revealedInOverflow)
        let hiddenCount = overflowSource.count - overflowRevealed.count
        let shouldShowFooter = hiddenCount > 0 && notifications.count > 4

        if let overflowCard = overflowRevealed.first ?? overflowSource.first, overflowSource.count == 1 || !overflowRevealed.isEmpty {
            let footer = shouldShowFooter ? "还有 \(hiddenCount) 条" : nil
            presentations.append(
                .card(
                    title: overflowCard.title,
                    body: overflowCard.body,
                    sessionId: overflowCard.sessionId,
                    footer: footer
                )
            )
        } else {
            presentations.append(.summary(hiddenCount: overflowSource.count))
        }

        return presentations
    }

    private func revealNextHiddenNotification() {
        let hiddenNotifications = hiddenNotifications()
        guard let nextHiddenID = hiddenNotifications.first?.id,
              let index = notifications.firstIndex(where: { $0.id == nextHiddenID }) else {
            return
        }

        notifications[index].revealedInOverflow = true
    }

    private func hiddenNotifications() -> [Notification] {
        Array(notifications.reversed().dropFirst(2)).filter { !$0.revealedInOverflow }
    }
}
