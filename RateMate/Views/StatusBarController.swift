import SwiftUI
import AppKit
import Combine

class StatusBarController: ObservableObject {
    static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var currentRateText = "🎧 --"
    @Published var isPopoverShown = false
    @Published var isTransitioning = false
    @Published var currentRate: Double = 0
    @Published var targetRate: Double = 0
    
    private init() {
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = currentRateText
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient
        popover?.animates = true
        
        let contentView = RateView()
            .environmentObject(self)
        
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }
    
    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if self?.isPopoverShown == true {
                self?.closePopover()
            }
        }
    }
    
    @objc private func togglePopover() {
        if isPopoverShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor?.start()
        isPopoverShown = true
    }
    
    private func closePopover() {
        popover?.performClose(nil)
        eventMonitor?.stop()
        isPopoverShown = false
    }
    
    func updateRate(_ rate: Double, isTransitioning: Bool = false, targetRate: Double? = nil) {
        self.currentRate = rate
        self.isTransitioning = isTransitioning
        
        if let target = targetRate {
            self.targetRate = target
            currentRateText = "🎧 \(formatRate(rate)) → \(formatRate(target))"
        } else {
            currentRateText = "🎧 \(formatRate(rate))"
        }
        
        statusItem?.button?.title = currentRateText
    }
    
    func showError() {
        currentRateText = "🎧 \(formatRate(currentRate)) ⚠️"
        statusItem?.button?.title = currentRateText
    }
    
    func showNoPermission() {
        currentRateText = "🎧 FDA Required"
        statusItem?.button?.title = currentRateText
    }
    
    private func formatRate(_ rate: Double) -> String {
        let kHz = rate / 1000.0
        if kHz == floor(kHz) {
            return "\(Int(kHz))"
        } else {
            return String(format: "%.1f", kHz)
        }
    }
}

class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}