import SwiftUI
import AppKit
import UserNotifications

enum BState { case working, inCall, onBreak, paused }

final class BreakScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var state = BState.working
    @Published var workSecs = 0
    @Published var breakLeft = 0
    @Published var pausedLeft = 0
    @Published var breakTotal = 0
    @Published var justFinished = false
    @Published var activity = Activity.all[0]
    @Published var activityStart = Date()
    @AppStorage("workMin") var workMin = 20
    @AppStorage("breakSec") var breakSec = 20
    @AppStorage("idleMin") var idleMin = 5
    @AppStorage("skipMin") var skipMin = 10
    @AppStorage("snoozeMin") var snoozeMin = 5
    let detector = CallDetector()
    var callNow = false, callEndedFor = 0, tick = 0
    var timer: Timer?
    let overlay = Overlay()
    let heads = HeadsUp()
    let nudges = Nudges()
    @AppStorage("breaksTaken") var taken = 0
    @AppStorage("breaksSkipped") var skipped = 0
    @AppStorage("statsDay") var statsDay = ""
    var stats: String { rollDay(); return "Today: \(taken) breaks · \(skipped) skipped · \(NudgeKind.doneToday) nudges done" }
    func rollDay() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let today = f.string(from: Date())
        if statsDay != today { statsDay = today; taken = 0; skipped = 0; NudgeKind.all.forEach { UserDefaults.standard.removeObject(forKey: "done_" + $0.key) } }
    }

    override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
        let n = UNUserNotificationCenter.current()
        n.delegate = self
        n.setNotificationCategories([UNNotificationCategory(identifier: "BREAK", actions: [UNNotificationAction(identifier: "START", title: "Start break", options: [.foreground])], intentIdentifiers: [])])
        n.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let d = DistributedNotificationCenter.default()
        d.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.away() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.away() }
        if let t = ProcessInfo.processInfo.environment["BLINQ_TEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let k = NudgeKind.all.first(where: { $0.key == t }) { self.nudges.fire(k) }
                else if t == "break" { self.startBreak() }
                else if t == "heads" { self.workSecs = self.interval - HeadsUp.lead }
            }
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)  // keep ticking while menus are open
        timer = t
    }

    var interval: Int { workMin * 60 }
    var label: String {
        switch state {
        case .paused: return "Paused"
        case .onBreak: return "Break"
        case .inCall: return "In call"
        default: let r = max(0, interval - workSecs); return String(format: "%d:%02d", r / 60, r % 60)
        }
    }

    func step() {
        tick += 1
        if tick % 2 == 0 { callNow = detector.inCall }
        switch state {
        case .paused:
            heads.hide()
            pausedLeft -= 1; if pausedLeft <= 0 { state = .working }
        case .onBreak:
            breakLeft -= 1; if breakLeft <= 0 { Sounds.play("breakEnd"); endBreak() }
        default:
            // Calls count toward fatigue and aren't subject to idle reset (you may just be listening).
            if callNow { heads.hide(); callEndedFor = 0; state = .inCall; workSecs += 1; return }
            if state == .inCall {
                workSecs += 1; callEndedFor += 1
                if callEndedFor < 30 { return }
                if workSecs >= interval { suggest() } else { state = .working }
                return
            }
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle >= Double(idleMin * 60) { workSecs = 0; nudges.reset(); heads.hide(); return }
            workSecs += 1
            if state == .working && !heads.visible && workSecs < interval - HeadsUp.lead - 5 { nudges.tick() }
            if state == .working && workSecs >= interval { startBreak() }
            else if state == .working && workSecs >= interval - HeadsUp.lead { if !heads.visible { pickActivity(); heads.show(self) } }
            else { heads.hide() }
        }
    }

    func suggest() {
        state = .working; workSecs = interval - snoozeMin * 60  // ignored suggestion → snooze
        let c = UNMutableNotificationContent()
        c.title = "Call ended — take a break?"; c.categoryIdentifier = "BREAK"
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    func startBreak() {
        if !heads.visible { pickActivity() }  // otherwise keep the one the heads-up promised
        heads.hide(); state = .onBreak; breakLeft = breakSec; breakTotal = breakSec
        activityStart = Date(); justFinished = false; Sounds.play("breakStart")
        overlay.show(self)
    }
    func endBreak() {
        rollDay()
        let done = state == .onBreak
        if done { taken += 1; justFinished = true }
        overlay.close(after: done ? 2 : 0); workSecs = 0; nudges.reset(); state = .working
    }
    func extend() { breakLeft += 30; breakTotal += 30 }
    func switchTo(_ a: Activity) { activity = a; activityStart = Date() }
    func pickActivity() { activity = Activity.all.filter { $0 != activity }.randomElement()! }
    func skip() { heads.hide(); rollDay(); skipped += 1; overlay.close(); workSecs = interval - skipMin * 60; state = .working }
    func snooze() { heads.hide(); overlay.close(); if state == .onBreak { state = .working; workSecs = interval - snoozeMin * 60 } else { workSecs = max(0, workSecs - snoozeMin * 60) } }
    func pause(_ m: Int) { heads.hide(); overlay.close(); state = .paused; pausedLeft = m * 60 }
    func resume() { state = .working }
    /// Screen locked or Mac sleeping: counts as a break.
    func away() { heads.hide(); nudges.reset(); if state == .onBreak { endBreak() } else { workSecs = 0 } }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
        if r.actionIdentifier == "START" || r.actionIdentifier == UNNotificationDefaultActionIdentifier { DispatchQueue.main.async { self.startBreak() } }
        h()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }
}

