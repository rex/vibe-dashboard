import Testing
@testable import VibeDashboard

/// Pins the toast bookkeeping in `AppState` — and, specifically, that dismissing a
/// toast also cancels its auto-dismiss timer (the handle is no longer discarded,
/// so there's no unbounded timer churn and a reused id can't fire a stale
/// dismissal). `AppState` is `@MainActor`, so the whole suite is too.
@Suite("AppState toasts")
@MainActor
struct AppStateToastTests {

    @Test("toast appends with a monotonically increasing id and arms one timer each")
    func toastAppendsAndArmsTimer() {
        let app = AppState()
        #expect(app.toasts.isEmpty)
        #expect(app.activeToastTimerIDs.isEmpty)

        let a = app.toast("a")
        let b = app.toast("b", "second one")
        #expect(b > a)                                   // ids never collide
        #expect(app.toasts.map(\.id) == [a, b])
        #expect(app.toasts.first?.title == "a")
        #expect(app.activeToastTimerIDs.sorted() == [a, b])   // one live timer per toast

        app.dismissToast(a); app.dismissToast(b)         // cancel the spawned sleeps
    }

    @Test("dismiss removes exactly one toast and tears down only its timer")
    func dismissRemovesOneAndCancelsTimer() {
        let app = AppState()
        let a = app.toast("a")
        let b = app.toast("b")

        app.dismissToast(a)
        #expect(app.toasts.map(\.id) == [b])             // only a removed
        #expect(app.activeToastTimerIDs.sorted() == [b]) // a's timer gone, b's kept

        app.dismissToast(b)
        #expect(app.toasts.isEmpty)
        #expect(app.activeToastTimerIDs.isEmpty)         // no leaked timer churn
    }

    @Test("dismissing an unknown id is a safe no-op")
    func dismissUnknownIsNoop() {
        let app = AppState()
        let a = app.toast("a")

        app.dismissToast(999_999)                        // never issued
        #expect(app.toasts.map(\.id) == [a])
        #expect(app.activeToastTimerIDs.sorted() == [a])

        app.dismissToast(a)
    }
}
