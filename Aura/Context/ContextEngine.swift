import Foundation
import Combine
import EventKit
import AppKit

/// Central hub that aggregates context from multiple detectors
/// Publishes current context state for widgets and automation
class ContextEngine: ObservableObject {
    static let shared = ContextEngine()
    
    // MARK: - Published Context State
    
    /// Currently active application
    @Published var currentApp: RunningApp?
    
    /// Focus/DND mode status
    @Published var isFocusMode: Bool = false
    @Published var focusModeName: String?
    
    /// Upcoming meeting
    @Published var upcomingMeeting: EKEvent?
    @Published var isInMeeting: Bool = false
    
    /// Battery state
    @Published var batteryLevel: Int = 100
    @Published var isCharging: Bool = false
    @Published var isLowPower: Bool = false
    
    /// Screen state
    @Published var isScreenSharing: Bool = false
    @Published var isScreenRecording: Bool = false
    
    /// Time context
    @Published var timeOfDay: TimeOfDay = .afternoon
    @Published var isWorkHours: Bool = true
    
    // MARK: - Detectors
    
    private let activeAppDetector = ActiveAppDetector()
    private let focusModeDetector = FocusModeDetector()
    private let calendarDetector = CalendarDetector()
    private let batteryDetector = BatteryDetector()
    private let screenShareDetector = ScreenShareDetector()
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        setupDetectors()
        startMonitoring()
    }
    
    private func setupDetectors() {
        // Active app changes
        activeAppDetector.$currentApp
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentApp)
        
        // Focus mode changes
        focusModeDetector.$isFocusMode
            .receive(on: DispatchQueue.main)
            .assign(to: &$isFocusMode)
        
        focusModeDetector.$focusModeName
            .receive(on: DispatchQueue.main)
            .assign(to: &$focusModeName)
        
        // Calendar changes
        calendarDetector.$upcomingMeeting
            .receive(on: DispatchQueue.main)
            .assign(to: &$upcomingMeeting)
        
        calendarDetector.$isInMeeting
            .receive(on: DispatchQueue.main)
            .assign(to: &$isInMeeting)
        
        // Battery changes
        batteryDetector.$level
            .receive(on: DispatchQueue.main)
            .assign(to: &$batteryLevel)
        
        batteryDetector.$isCharging
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCharging)
        
        batteryDetector.$isLowPower
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLowPower)
        
        // Screen share changes
        screenShareDetector.$isSharing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScreenSharing)
        
        screenShareDetector.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScreenRecording)
    }
    
    private func startMonitoring() {
        // Start all detectors
        activeAppDetector.startMonitoring()
        focusModeDetector.startMonitoring()
        calendarDetector.startMonitoring()
        batteryDetector.startMonitoring()
        screenShareDetector.startMonitoring()
        
        // Time-based context refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateTimeContext()
        }
        updateTimeContext()
    }
    
    private func updateTimeContext() {
        let hour = Calendar.current.component(.hour, from: Date())
        
        timeOfDay = switch hour {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<21: .evening
        default: .night
        }
        
        // Work hours: 9 AM - 6 PM on weekdays
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isWeekday = (2...6).contains(weekday)
        isWorkHours = isWeekday && (9...18).contains(hour)
    }
    
    // MARK: - Public API
    
    func refresh() {
        activeAppDetector.refresh()
        focusModeDetector.refresh()
        calendarDetector.refresh()
        batteryDetector.refresh()
        screenShareDetector.refresh()
        updateTimeContext()
    }
    
    func stopMonitoring() {
        refreshTimer?.invalidate()
        activeAppDetector.stopMonitoring()
        focusModeDetector.stopMonitoring()
        calendarDetector.stopMonitoring()
        batteryDetector.stopMonitoring()
        screenShareDetector.stopMonitoring()
    }
}

// MARK: - Supporting Types

enum TimeOfDay: String {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case night = "Night"
}

struct RunningApp: Equatable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?
    
    var isProductivity: Bool {
        let productivityApps = [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.sublimetext",
            "com.apple.Notes",
            "com.apple.iWork.Pages",
            "com.apple.iWork.Numbers",
            "com.apple.iWork.Keynote"
        ]
        return productivityApps.contains(bundleIdentifier)
    }
    
    var isCommunication: Bool {
        let communicationApps = [
            "com.apple.mail",
            "com.tinyspeck.slackmacgap",
            "com.microsoft.teams",
            "com.apple.MobileSMS",
            "us.zoom.xos",
            "com.google.Chrome",
            "com.apple.Safari"
        ]
        return communicationApps.contains(bundleIdentifier)
    }
    
    var isEntertainment: Bool {
        let entertainmentApps = [
            "com.apple.Music",
            "com.spotify.client",
            "com.apple.TV",
            "com.netflix.Netflix",
            "com.apple.podcasts"
        ]
        return entertainmentApps.contains(bundleIdentifier)
    }
}
