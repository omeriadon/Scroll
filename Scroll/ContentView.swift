//
//  ContentView.swift
//  Scroll
//
//  Created by Adon Omeri on 18/3/2026.
//

import ColorfulX
import Network
import SwiftUI

struct ContentView: View {
	@Environment(PhoneConnectivityManager.self) private var connectivityManager
	@State private var scrollPadViewModel = ScrollPadViewModel()

	@State private var isSettingsPresented = false
	@State private var isConnectionPresented = false

	@State private var sensitivity = ScrollSettingsStore.sensitivity
	@State private var invertDirection = ScrollSettingsStore.invertDirection
	@State private var smoothingMode = ScrollSettingsStore.smoothingMode
	@State private var inputResolution = ScrollSettingsStore.inputResolution
	@State private var maxSendRateHz = ScrollSettingsStore.maxSendRateHz

	@Namespace private var namespace

	@State private var color: [Color] = [.black, .gray, .black, .gray, .black, .black]
	@State private var speed: Double = 0.3
	@State private var bias: Double = 0.01
	@State private var noise: Double = 40.0
	@State private var transition: Double = 3.5
	@State private var frameLimit: Int = 60
	@State private var renderScale: Double = 1.0

	var body: some View {
		NavigationStack {
			ZStack {
				ColorfulView(
					color: $color,
					speed: $speed,
					bias: $bias,
					noise: $noise,
					transitionSpeed: $transition,
					frameLimit: $frameLimit,
					renderScale: $renderScale
				)
				.ignoresSafeArea()

				VStack(spacing: 16) {
					diagnosticsStrip

					Spacer()

					ScrollPadView(touchLocation: scrollPadViewModel.touchLocation)
						.gesture(scrollDragGesture)
						.accessibilityLabel("Scrolling pad")
						.accessibilityHint("Drag up or down with one finger to scroll your Mac")
						.padding(15)
						.ignoresSafeArea()
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button {
						isConnectionPresented = true
					} label: {
						Text("\(connectivityManager.macConnectionStatus.uppercased())")
							.fontDesign(.monospaced)
							.font(.caption)
							.fixedSize()
							.padding(11)
							.glassEffect(.regular.tint(connectivityManager.isConnectedToMac ? .green : .red).interactive())
							.foregroundStyle(connectivityManager.isConnectedToMac ? .black : .white)
					}
					.buttonStyle(.plain)
				}
				.sharedBackgroundVisibility(.hidden)
				.matchedTransitionSource(id: "thing2", in: namespace)

				ToolbarItem(placement: .topBarTrailing) {
					Button {
						isSettingsPresented = true
					} label: {
						Label("Settings", systemImage: "slider.horizontal.3")
					}
				}
				.matchedTransitionSource(id: "thing", in: namespace)

				ToolbarItem(placement: .title) {
					Text("Scroll")
						.fontDesign(.monospaced)
				}
			}
			.sheet(isPresented: $isSettingsPresented) {
				settingsSheet
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.hidden)
					.navigationTransition(
						.zoom(sourceID: "thing", in: namespace)
					)
			}
			.sheet(isPresented: $isConnectionPresented) {
				connectView
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.hidden)
					.navigationTransition(
						.zoom(sourceID: "thing2", in: namespace)
					)
			}
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
				connectivityManager.flushIfPending() // ← flush any rate-gated tail sample
			}
	}

	private var settingsSheet: some View {
		return NavigationStack {
			List {
				Section("Scroll") {
					Slider(value: bindingForSensitivity, in: 0.2...3.0) {
						Text("SPEED")
							.font(.system(.caption, design: .monospaced).weight(.semibold))
					} minimumValueLabel: {
						AnyView(EmptyView())
					} maximumValueLabel: {
						AnyView(
							Text(sensitivity.formatted(.number.precision(.fractionLength(2))))
								.contentTransition(.numericText())
								.animation(.easeInOut, value: sensitivity)
								.font(.system(.title3, design: .monospaced))
						)
					}
					.onChange(of: sensitivity) { oldValue, newValue in
						let stepped = (newValue * 10).rounded()
						let oldStepped = (oldValue * 10).rounded()
						if stepped != oldStepped {
							UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
						}
					}

					Toggle(isOn: bindingForInvertDirection) {
						Text("Invert")
							.fontDesign(.monospaced)
					}
					.toggleStyle(.switch)

					Picker("Smoothness", selection: bindingForSmoothingMode) {
						Text("Adapt")
							.tag(ScrollSmoothingMode.adaptive)
						Text("Linear")
							.tag(ScrollSmoothingMode.linear)
					}
					.onChange(of: smoothingMode) {
						UIImpactFeedbackGenerator(style: .medium).impactOccurred()
					}
					.pickerStyle(.segmented)
				}

				Section("Performance") {
					Picker("Resolution", selection: bindingForInputResolution) {
						ForEach(ScrollInputResolution.allCases, id: \.self) { option in
							Text(option.displayName).tag(option)
						}
					}
					.onChange(of: inputResolution) {
						UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
					}
					.pickerStyle(.segmented)

					Slider(value: bindingForMaxSendRateHz, in: 30...120, step: 10) {
						Text("Send Rate")
							.font(.system(.caption, design: .monospaced).weight(.semibold))
					} minimumValueLabel: {
						AnyView(EmptyView())
					} maximumValueLabel: {
						AnyView(
							Text(String(format: "%3d HZ", Int(maxSendRateHz)))
								.contentTransition(.numericText())
								.animation(.easeInOut, value: maxSendRateHz)
								.font(.system(.title3, design: .monospaced))
						)
					}
					.onChange(of: maxSendRateHz) { oldValue, newValue in
						let stepped = (newValue * 10).rounded()
						let oldStepped = (oldValue * 10).rounded()
						if stepped != oldStepped {
							UIImpactFeedbackGenerator(style: .medium).impactOccurred()
						}
					}
				}
			}
			.listStyle(.insetGrouped)
			.font(.system(.body, design: .monospaced))
			.toolbarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .title) {
					Text("Settings")
						.fontDesign(.monospaced)
				}

				ToolbarItem(placement: .topBarTrailing) {
					Button(role: .confirm) {
						isSettingsPresented = false
					}
				}
			}
		}
	}

	private var connectView: some View {
		let hosts = connectivityManager.discoveredHosts

		return NavigationStack {
			List {
				if hosts.isEmpty {
					Text("Searching for hosts…")
						.foregroundStyle(.secondary)
				} else {
					ForEach(Array(hosts.enumerated()), id: \.offset) { _, host in
						Button {
							withAnimation(.easeInOut) {
								if connectivityManager.isConnectedToMac {
									connectivityManager.disconnect()
								} else {
									connectivityManager.connectToHost(host)
									Task {
										try? await Task.sleep(for: .seconds(0.6))
										isConnectionPresented = false
									}
								}
							}
						} label: {
							HStack {
								Text(hostDisplayName(for: host))
									.font(.title2)

								Spacer()

								Image(systemName: connectivityManager.isConnectedToMac ? "checkmark" : "arrow.right")
									.contentTransition(.symbolEffect(.replace.upUp.wholeSymbol, options: .nonRepeating))
									.imageScale(.large)
									.bold()
							}
							.foregroundStyle(connectivityManager.isConnectedToMac ? .green : .blue)
							.animation(.easeInOut, value: connectivityManager.isConnectedToMac)

						}
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .title) {
					Text("Connect to Mac")
						.fontDesign(.monospaced)
				}

				ToolbarItem(placement: .topBarTrailing) {
					Button(role: .confirm) {
						isConnectionPresented = false
					}
				}
			}
		}
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
			get: { !invertDirection },
			set: { newValue in
				invertDirection = !newValue
				connectivityManager.updateSettings(
					sensitivity: sensitivity,
					inverted: !newValue,
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

struct InnerHeightPreferenceKey: PreferenceKey {
	static let defaultValue: CGFloat = .zero
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = nextValue()
	}
}

#Preview {
	ContentView()
		.environment(PhoneConnectivityManager.shared)
}
