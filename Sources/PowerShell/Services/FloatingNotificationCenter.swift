import Foundation

@MainActor
final class FloatingNotificationCenter {
    struct Notification: Identifiable, Equatable {
        let id: UUID
        let title: String
        let body: String
        let sessionId: String
    }

    enum Presentation: Equatable {
        case card(title: String, body: String, sessionId: String, footer: String?)
        case summary(hiddenCount: Int)
    }

    private var notifications: [Notification] = []
    private var revealedOverflowID: UUID?

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
        let visibleIDs = Set(visibleNotifications().map(\.id))
        let removedVisibleNotification = visibleIDs.contains(id)

        notifications.removeAll { $0.id == id }

        if revealedOverflowID == id {
            revealedOverflowID = nil
        }

        if removedVisibleNotification {
            normalizeOverflowReveal(afterRemovingVisibleNotification: true)
        } else {
            normalizeOverflowReveal(afterRemovingVisibleNotification: false)
        }
    }

    func advanceOverflow() {
        let hidden = hiddenOverflowNotifications()
        guard !hidden.isEmpty else {
            return
        }

        if let revealedOverflowID,
           let currentIndex = hidden.firstIndex(where: { $0.id == revealedOverflowID }) {
            let nextIndex = hidden.index(after: currentIndex)
            self.revealedOverflowID = nextIndex < hidden.endIndex ? hidden[nextIndex].id : hidden.first?.id
        } else {
            revealedOverflowID = hidden.first?.id
        }
    }

    func presentations() -> [Presentation] {
        let visible = visibleNotifications()
        let hidden = hiddenOverflowNotifications()
        let revealed = revealedOverflowNotification(in: hidden)

        var result = visible.map {
            Presentation.card(title: $0.title, body: $0.body, sessionId: $0.sessionId, footer: nil)
        }

        if hidden.isEmpty {
            return result
        }

        if let revealed {
            let hiddenCount = hidden.count - 1
            let footer = hiddenCount > 0 ? "还有 \(hiddenCount) 条" : nil
            result.append(
                .card(
                    title: revealed.title,
                    body: revealed.body,
                    sessionId: revealed.sessionId,
                    footer: footer
                )
            )
        } else if hidden.count == 1 {
            let overflow = hidden[0]
            result.append(
                .card(
                    title: overflow.title,
                    body: overflow.body,
                    sessionId: overflow.sessionId,
                    footer: nil
                )
            )
        } else {
            result.append(.summary(hiddenCount: hidden.count))
        }

        return result
    }

    private func visibleNotifications() -> [Notification] {
        Array(notifications.reversed().prefix(2))
    }

    private func hiddenOverflowNotifications() -> [Notification] {
        Array(notifications.reversed().dropFirst(2))
    }

    private func revealedOverflowNotification(in hidden: [Notification]) -> Notification? {
        guard let revealedOverflowID else {
            return nil
        }

        return hidden.first(where: { $0.id == revealedOverflowID })
    }

    private func normalizeOverflowReveal(afterRemovingVisibleNotification: Bool) {
        let hidden = hiddenOverflowNotifications()

        guard hidden.count > 1 else {
            revealedOverflowID = nil
            return
        }

        if afterRemovingVisibleNotification {
            revealedOverflowID = hidden.first?.id
            return
        }

        guard let revealedOverflowID,
              hidden.contains(where: { $0.id == revealedOverflowID }) else {
            self.revealedOverflowID = nil
            return
        }
    }
}
