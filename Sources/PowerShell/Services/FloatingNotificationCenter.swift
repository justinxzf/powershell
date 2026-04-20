import Foundation

@MainActor
final class FloatingNotificationCenter {
    enum Presentation: Equatable {
        case card(title: String, body: String, sessionId: String, footer: String?)
    }

    private struct SessionAggregate {
        let sessionId: String
        var title: String
        var body: String
        var additionalCount: Int
    }

    private var sessionAggregates: [SessionAggregate] = []

    func enqueue(title: String, body: String, sessionId: String) {
        if let index = sessionAggregates.firstIndex(where: { $0.sessionId == sessionId }) {
            var aggregate = sessionAggregates.remove(at: index)
            aggregate.title = title
            aggregate.body = body
            aggregate.additionalCount += 1
            sessionAggregates.insert(aggregate, at: 0)
            return
        }

        sessionAggregates.insert(
            SessionAggregate(
                sessionId: sessionId,
                title: title,
                body: body,
                additionalCount: 0
            ),
            at: 0
        )
    }

    func dismiss(sessionId: String) {
        sessionAggregates.removeAll { $0.sessionId == sessionId }
    }

    func presentations() -> [Presentation] {
        sessionAggregates.map { aggregate in
            .card(
                title: aggregate.title,
                body: aggregate.body,
                sessionId: aggregate.sessionId,
                footer: aggregate.additionalCount > 0 ? "还有 \(aggregate.additionalCount) 条" : nil
            )
        }
    }
}
