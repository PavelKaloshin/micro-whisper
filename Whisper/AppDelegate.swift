import Cocoa
import SwiftUI
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var globalEventMonitor: Any?
    private var lastGlobeKeyTime: Date?
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching called")
        
        // Migrate API key from old file-based storage to Keychain
        KeychainService.shared.migrateFromFileIfNeeded()
        
        setupStatusBar()
        setupHotKey()
        debugLog("Setup completed, statusItem = \(String(describing: statusItem))")
    }
    
    private func debugLog(_ message: String) {
        let debugPath = "/tmp/whisper_debug.txt"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        if let handle = FileHandle(forWritingAtPath: debugPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: debugPath, atomically: true, encoding: .utf8)
        }
    }
    
    func setupStatusBar() {
        debugLog("setupStatusBar starting")
        guard statusItem == nil else { 
            debugLog("statusItem already exists")
            return 
        }
        
        // Create status item with menu (more reliable than popover)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        debugLog("created statusItem: \(item)")
        
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisper")
            button.image?.isTemplate = true
            debugLog("button configured with image")
        }
        
        // Create menu
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecordingMenu), keyEquivalent: "")
        recordItem.target = self
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Whisper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        item.menu = menu
        statusItem = item
        debugLog("setupStatusBar completed with menu")
    }
    
    @objc func toggleRecordingMenu() {
        Task { @MainActor in
            await Self.toggleRecording()
        }
    }
    
    @objc func togglePopover() {
        guard let statusItem = statusItem else { return }
        
        // Lazy create popover
        if popover == nil {
            let pop = NSPopover()
            pop.contentSize = NSSize(width: 300, height: 400)
            pop.behavior = .transient
            pop.contentViewController = NSHostingController(rootView: 
                MenuBarView().environmentObject(AppState.shared)
            )
            popover = pop
        }
        
        guard let popover = popover, let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView().environmentObject(AppState.shared)
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Whisper Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 500, height: 450))
            window.center()
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupHotKey() {
        // Use Globe key (Fn key) - double press to activate
        // Globe key has keyCode 63 (kVK_Function)
        setupGlobeKeyMonitor()
        
        // Load saved fallback hotkey or use default (Cmd+Shift+9)
        let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? UInt32 ?? 25
        let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        
        updateHotKey(keyCode: savedKeyCode, modifiers: NSEvent.ModifierFlags(rawValue: UInt(savedModifiers)))
    }
    
    private func setupGlobeKeyMonitor() {
        // Monitor for Globe/Fn key (keyCode 63)
        // We use flagsChanged event since Globe key is a modifier
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleGlobeKey(event: event)
        }
        
        // Also add local monitor for when app is focused
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleGlobeKey(event: event)
            return event
        }
    }
    
    private func handleGlobeKey(event: NSEvent) {
        // Globe key detection: keyCode 63 (kVK_Function) is the Fn/Globe key.
        // A single physical press produces two flagsChanged events: key-down and key-up.
        // We must only count key-DOWN events (when .function modifier is being SET)
        // to avoid a single press-release being counted as two taps.
        
        guard event.type == .flagsChanged else { return }
        guard event.keyCode == 63 else { return }
        guard event.modifierFlags.contains(.function) else { return }
        
        let now = Date()
        
        if let lastTime = lastGlobeKeyTime {
            let timeDiff = now.timeIntervalSince(lastTime)
            
            // Double press within 0.4 seconds
            if timeDiff < 0.4 && timeDiff > 0.05 {
                lastGlobeKeyTime = nil
                Task { @MainActor in
                    await Self.toggleRecording()
                }
                return
            }
        }
        
        lastGlobeKeyTime = now
    }
    
    @MainActor
    private static func toggleRecording() async {
        let appState = AppState.shared
        
        if appState.isRecording {
            await appState.stopRecordingAndProcess()
        } else {
            appState.startRecording()
        }
    }
    
    @MainActor
    func updateStatusIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: isRecording ? "mic.fill" : "mic",
            accessibilityDescription: "Whisper"
        )
        // Tint red when recording
        if isRecording {
            button.contentTintColor = .red
        } else {
            button.contentTintColor = nil
        }
    }
    
    func updateHotKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        // Convert keyCode to HotKey's Key type
        guard let key = Key(carbonKeyCode: keyCode) else {
            print("Invalid keyCode: \(keyCode)")
            return
        }
        
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = {
            Task { @MainActor in
                await Self.toggleRecording()
            }
        }
    }
}

