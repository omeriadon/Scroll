//
//  ContentView.swift
//  Scroll
//
//  Created by Adon Omeri on 18/3/2026.
//

import SwiftUI
import Network

struct ContentView: View {
    @Environment(PhoneConnectivityManager.self) private var connectivityManager
    @State private var scrollPadViewModel = ScrollPadViewModel()
    @State private var isSettingsPresented = false

    @State private var sensitivity = ScrollSettingsStore.sensitivity
    @State private var invertDirection = ScrollSettingsStore.invertDirection
    @State private var smoothingMode = ScrollSettingsStore.smoothingMode
    @State private var inputResolution = ScrollSettingsStore.inputResolution
    @State private var maxSendRateHz = ScrollSettingsStore.maxSendRateHz

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.95),
                        Color.gray.opacity(0.78),
                        Color.black.opacity(0.93)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    connectionStrip

                    ScrollPadView(touchLocation: scrollPadViewModel.touchLocation)
                        .frame(maxWidth: 560, maxHeight: 560)
                        .aspectRatio(1, contentMode: .fit)
                        .gesture(scrollDragGesture)
                        .padding(.horizontal, 18)
                        .accessibilityLabel("Scrolling pad")
                        .accessibilityHint("Drag up or down with one finger to scroll your Mac")

                    diagnosticsStrip
                }
                .padding(.vertical, 10)
            }
            .safeAreaInset(edge: .top) {
                topToolbar
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }
            .navigationTitle("Scroll")
            .toolbarTitleDisplayMode(.inline)
            .font(.system(.body, design: .monospaced))
            .onAppear(perform: syncLocalStateFromDefaults)
        }
    }

    private var scrollDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrollPadViewModel.touchLocation == nil {
                    scrollPadViewModel.beginInteraction(at: value.location)
                }

                scrollPadViewModel.updateInteraction(
                    location: value.location,
                    translationY: value.translation.height,
                    minimumDeltaStep: inputResolution.quantizationStep
                ) { delta, velocity in
                    connectivityManager.sendScrollDelta(delta: delta, velocity: velocity)
                }
            }
            .onEnded { _ in
                scrollPadViewModel.endInteraction()
            }
    }

    private var topToolbar: some View {
        HStack(spacing: 12) {
            Text("LIVE • \(connectivityManager.macConnectionStatus.uppercased())")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button {
                isSettingsPresented = true
            } label: {
                Label("SETTINGS", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
				.presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var settingsSheet: some View {
        let hosts = connectivityManager.discoveredHosts

        return NavigationStack {
            List {
                Section("Scroll") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SPEED")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                        Slider(value: bindingForSensitivity, in: 0.2...3.0, step: 0.05)
                        Text(sensitivity.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Toggle("INVERT", isOn: bindingForInvertDirection)
                        .toggleStyle(.switch)

                    Picker("SMOOTH", selection: bindingForSmoothingMode) {
                        Text("ADAPT").tag(ScrollSmoothingMode.adaptive)
                        Text("LINEAR").tag(ScrollSmoothingMode.linear)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Performance") {
                    Picker("RESOLUTION", selection: bindingForInputResolution) {
                        ForEach(ScrollInputResolution.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SEND RATE")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                        Slider(value: bindingForMaxSendRateHz, in: 30...120, step: 10)
                        Text("\(Int(maxSendRateHz)) HZ")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                Section("Mac Hosts") {
                    if hosts.isEmpty {
                        Text("Searching for hosts…")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(hosts.enumerated()), id: \.offset) { _, host in
                            Button {
                                connectivityManager.connectToHost(host)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hostDisplayName(for: host))
                                        Text("tap to connect")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                            }
                        }
                    }

                    if connectivityManager.isConnectedToMac {
                        Button("Disconnect") {
                            connectivityManager.disconnect()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .font(.system(.body, design: .monospaced))
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isSettingsPresented = false
                    }
                }
            }
        }
    }

    private var connectionStrip: some View {
        HStack {
            Circle()
                .fill(connectivityManager.isConnectedToMac ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(connectivityManager.macConnectionStatus.uppercased())
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var diagnosticsStrip: some View {
        HStack(spacing: 14) {
            Text(lastSequenceText)
            Text(lastDeltaText)
            Text(lastVelocityText)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.2), in: Capsule())
    }

    private var lastSequenceText: String {
        guard let command = connectivityManager.lastCommand else { return "SEQ: --" }
        return "SEQ: \(command.sequence)"
    }

    private var lastDeltaText: String {
        guard let command = connectivityManager.lastCommand else { return "Δ: --" }
        return "Δ: \(command.delta.formatted(.number.precision(.fractionLength(3))))"
    }

    private var lastVelocityText: String {
        guard let command = connectivityManager.lastCommand else { return "VEL: --" }
        return "VEL: \(command.velocity.formatted(.number.precision(.fractionLength(3))))"
    }

    private func hostDisplayName(for result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint {
            return name
        }

        return String(describing: result.endpoint)
    }

    private var bindingForSensitivity: Binding<Double> {
        Binding(
            get: { sensitivity },
            set: { newValue in
                sensitivity = newValue
                connectivityManager.updateSettings(
                    sensitivity: newValue,
                    inverted: invertDirection,
                    smoothingMode: smoothingMode
                )
            }
        )
    }

    private var bindingForInvertDirection: Binding<Bool> {
        Binding(
            get: { invertDirection },
            set: { newValue in
                invertDirection = newValue
                connectivityManager.updateSettings(
                    sensitivity: sensitivity,
                    inverted: newValue,
                    smoothingMode: smoothingMode
                )
            }
        )
    }

    private var bindingForSmoothingMode: Binding<ScrollSmoothingMode> {
        Binding(
            get: { smoothingMode },
            set: { newValue in
                smoothingMode = newValue
                connectivityManager.updateSettings(
                    sensitivity: sensitivity,
                    inverted: invertDirection,
                    smoothingMode: newValue
                )
            }
        )
    }

    private var bindingForInputResolution: Binding<ScrollInputResolution> {
        Binding(
            get: { inputResolution },
            set: { newValue in
                inputResolution = newValue
                connectivityManager.updatePerformanceSettings(
                    inputResolution: newValue,
                    maxSendRateHz: maxSendRateHz
                )
            }
        )
    }

    private var bindingForMaxSendRateHz: Binding<Double> {
        Binding(
            get: { maxSendRateHz },
            set: { newValue in
                maxSendRateHz = newValue
                connectivityManager.updatePerformanceSettings(
                    inputResolution: inputResolution,
                    maxSendRateHz: newValue
                )
            }
        )
    }

    private func syncLocalStateFromDefaults() {
        sensitivity = ScrollSettingsStore.sensitivity
        invertDirection = ScrollSettingsStore.invertDirection
        smoothingMode = ScrollSettingsStore.smoothingMode
        inputResolution = ScrollSettingsStore.inputResolution
        maxSendRateHz = ScrollSettingsStore.maxSendRateHz
    }
}

#Preview {
    ContentView()
        .environment(PhoneConnectivityManager.shared)
}
