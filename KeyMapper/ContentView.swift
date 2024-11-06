//
//  ContentView.swift
//  KeyMapper
//
//  Created by 杜昊霖 on 2024/10/30.
//

import SwiftUI
import Cocoa

// MARK: - EventMonitor Class (Handles Global Mouse Event Monitor)

class EventMonitor: NSObject {
    static let shared = EventMonitor()
    var mouseClickHandler: ((CGPoint) -> Void)?

    override init() {
        super.init()
        // Setup global mouse click monitor
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        guard let mouseEventMonitor = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: EventMonitor.mouseClickCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("Unable to create mouse click monitor.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, mouseEventMonitor, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
    }

    // Static callback function that forwards the event to the instance handler
    private static let mouseClickCallback: CGEventTapCallBack = { _, _, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passRetained(event) }
        let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
        
        // Get mouse location on screen
        let location = NSEvent.mouseLocation
        monitor.mouseClickHandler?(location)
        
        return Unmanaged.passRetained(event)
    }
}

// MARK: - ContentView (Main User Interface)

struct ContentView: View {
    @State private var mappings: [Character: CGPoint] = [:]
    @State private var showPositionPicker = false
    @State private var selectedKey: Character = "A" // Default key to assign position
    @State private var isOverlayVisible = false
    @State private var isSimulatingClick = false // Track simulation mode state

    var body: some View {
        VStack {
            Text("KeyMapper App")
                .font(.largeTitle)
                .padding()

            // Display mapped keys and their positions
            List(mappings.keys.sorted(), id: \.self) { key in
                HStack {
                    Text("Key \(key)")
                    Spacer()
                    Text("Position: \(NSStringFromCGPoint(mappings[key]!))")
                }
            }
            .frame(maxWidth: .infinity)
            .listStyle(PlainListStyle())

            Button("Set Position with Mouse") {
                // Hide the app window and show the transparent overlay
                hideAppWindow()
                showPositionPicker = true
                isOverlayVisible = true
            }
            .padding()

            Button("Start Simulation") {
                // Start simulating click when a key is pressed
                isSimulatingClick = true
            }
            .padding()

            Button("Stop Simulation") {
                // Stop simulating click
                isSimulatingClick = false
            }
            .padding()

        }
        .onAppear {
            // Start monitoring mouse clicks
            EventMonitor.shared.mouseClickHandler = { location in
                if showPositionPicker {
                    // Only update the coordinates if we're in position picking mode
                    let invertedLocation = CGPoint(x: location.x, y: NSScreen.main!.frame.size.height - location.y) // Invert y-axis
                    mappings[selectedKey] = invertedLocation
                    showPositionPicker = false // Close picker when position is set
                    isOverlayVisible = false // Hide overlay when position is set
                    showAppWindow() // Show app window again
                }
            }

            // Start listening for key events (only trigger for straight A key, not Shift+A)
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if let key = event.characters?.first, isSimulatingClick, let point = mappings[key] {
                    simulateClick(at: point)
                }
            }
        }
        .overlay(
            // Transparent gray overlay that covers the entire screen
            Group {
                if isOverlayVisible {
                    Color.gray.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            // Handle tap gesture on the overlay to capture position
                            // Position will be captured via the event monitor's handler
                        }
                }
            }
        )
    }

    func NSStringFromCGPoint(_ point: CGPoint) -> String {
        return "(\(point.x), \(point.y))"
    }

    func simulateClick(at point: CGPoint) {
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        upEvent?.post(tap: .cghidEventTap)
    }

    // Hide the main app window
    func hideAppWindow() {
        if let appWindow = NSApplication.shared.windows.first {
            appWindow.orderOut(nil)
        }
    }

    // Show the main app window
    func showAppWindow() {
        if let appWindow = NSApplication.shared.windows.first {
            appWindow.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - PositionPicker View (For Capturing Mouse Position)

struct PositionPicker: View {
    var onConfirm: (CGPoint) -> Void

    var body: some View {
        VStack {
            Text("Click anywhere on the screen to set the position")
                .padding()
            MouseRegion(onConfirm: onConfirm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.5))
                .cornerRadius(8)
        }
        .padding()
    }
}

// MARK: - MouseRegion View (To Track Mouse Location)

struct MouseRegion: NSViewRepresentable {
    var onConfirm: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        addTracking(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No need to update here
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: MouseRegion

        init(_ parent: MouseRegion) {
            self.parent = parent
        }

        @objc func handleMouseUp(_ event: NSEvent) {
            parent.onConfirm(event.locationInWindow)
        }

        @objc func handleMouseMoved(_ event: NSEvent) {
            // Track mouse movement if needed
        }
    }

    func addTracking(to view: NSView) {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .mouseMoved]
        let trackingArea = NSTrackingArea(rect: view.bounds, options: options, owner: Coordinator(self), userInfo: nil)
        view.addTrackingArea(trackingArea)
    }
}
