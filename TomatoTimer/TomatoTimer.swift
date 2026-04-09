import Foundation
import UserNotifications
import Combine
import SwiftUI

enum TomatoMode: String, CaseIterable {
    case focus = "Focus"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"

    var duration: TimeInterval {
        switch self {
        case .focus:      return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak:  return 15 * 60
        }
    }

    var color: Color {
        switch self {
        case .focus:      return Color(red: 1.0, green: 0.30, blue: 0.18)   // tomato red
        case .shortBreak: return Color(red: 0.24, green: 0.81, blue: 0.56)  // mint green
        case .longBreak:  return Color(red: 0.36, green: 0.54, blue: 0.96)  // soft blue
        }
    }

    var emoji: String {
        switch self {
        case .focus:      return "🍅"
        case .shortBreak: return "☕️"
        case .longBreak:  return "🌿"
        }
    }

    var completionTitle: String {
        switch self {
        case .focus:      return "Focus session complete!"
        case .shortBreak: return "Break's over!"
        case .longBreak:  return "Long break done!"
        }
    }

    var completionBody: String {
        switch self {
        case .focus:      return "Great work. Time for a break."
        case .shortBreak: return "Ready to get back to it?"
        case .longBreak:  return "Refreshed and ready to focus?"
        }
    }

    var nextMode: TomatoMode {
        switch self {
        case .focus:      return .shortBreak
        case .shortBreak: return .focus
        case .longBreak:  return .focus
        }
    }
}

@MainActor
class TomatoTimer: ObservableObject {
    // MARK: - Published state
    @Published var mode: TomatoMode = .focus
    @Published var timeLeft: TimeInterval = TomatoMode.focus.duration
    @Published var isRunning: Bool = false
    @Published var completedSessions: Int = 0
    @Published var totalFocusedMinutes: Int = 0
    @Published var dailyStreak: Int = 0
    @Published var justCompleted: Bool = false
    
    // MARK: - Private
    private var timer: Timer?
    private var endDate: Date?          // when the current session will end (wall clock)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let notificationID = "tomato.session.end"
    
    // Persist streak/stats across launches
    private let defaults = UserDefaults.standard
    
    init() {
        completedSessions   = defaults.integer(forKey: "completedSessions")
        totalFocusedMinutes = defaults.integer(forKey: "totalFocusedMinutes")
        dailyStreak         = defaults.integer(forKey: "dailyStreak")
        checkStreakReset()
    }
    
    // MARK: - Controls
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        endDate = Date().addingTimeInterval(timeLeft)
        scheduleNotification(in: timeLeft)
        startBackgroundTask()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func pause() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        endDate = nil
        cancelNotification()
        endBackgroundTask()
    }
    
    func reset() {
        pause()
        timeLeft = mode.duration
        justCompleted = false
    }
    
    func resetStats() {
        completedSessions = 0
        totalFocusedMinutes = 0
        dailyStreak = 0
        saveStats()
    }

    func skip() {
        pause()
        advance()
    }

    func setMode(_ newMode: TomatoMode) {
        pause()
        mode = newMode
        timeLeft = newMode.duration
        justCompleted = false
    }

    // MARK: - Tick

    private func tick() {
        guard let end = endDate else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            timeLeft = 0
            sessionComplete()
        } else {
            timeLeft = remaining
        }
    }

    // MARK: - Session lifecycle

    private func sessionComplete() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        endDate = nil
        endBackgroundTask()
        justCompleted = true

        if mode == .focus {
            completedSessions += 1
            totalFocusedMinutes += 25
            saveStats()
            updateStreak()
        }

        // Auto-advance after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.advance()
            // auto start next session
            self?.start()
        }
    }

    private func advance() {
        // Every 4 focus sessions → long break
        let next: TomatoMode
        if mode == .focus && completedSessions % 4 == 0 && completedSessions > 0 {
            next = .longBreak
        } else {
            next = mode.nextMode
        }
        mode = next
        timeLeft = next.duration
        justCompleted = false
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("Notification permission error: \(error)") }
        }
    }

    private func scheduleNotification(in seconds: TimeInterval) {
        cancelNotification()
        let content = UNMutableNotificationContent()
        content.title = mode.completionTitle
        content.body  = mode.completionBody
        content.sound = .defaultCritical
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
        UNUserNotificationCenter.current()
            .setBadgeCount(0)
    }

    // MARK: - Background task (buys ~30s of extra CPU time when backgrounded)

    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PomodoroTimer") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Stats & Streak

    private func saveStats() {
        defaults.set(completedSessions,   forKey: "completedSessions")
        defaults.set(totalFocusedMinutes, forKey: "totalFocusedMinutes")
    }

    private func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastActiveDate = defaults.object(forKey: "lastActiveDate") as? Date
        if let last = lastActiveDate {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
            if daysSince == 0 {
                // same day, no change
            } else if daysSince == 1 {
                dailyStreak += 1
            } else {
                dailyStreak = 1
            }
        } else {
            dailyStreak = 1
        }
        defaults.set(today,        forKey: "lastActiveDate")
        defaults.set(dailyStreak,  forKey: "dailyStreak")
    }

    private func checkStreakReset() {
        guard let last = defaults.object(forKey: "lastActiveDate") as? Date else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
        if days > 1 { dailyStreak = 0; defaults.set(0, forKey: "dailyStreak") }
    }

    // MARK: - Helpers

    var progress: Double {
        guard mode.duration > 0 else { return 1 }
        return timeLeft / mode.duration
    }

    var formattedTime: String {
        let minutes = Int(timeLeft) / 60
        let seconds = Int(timeLeft) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var sessionDotsCompleted: Int {
        completedSessions % 4
    }
}
