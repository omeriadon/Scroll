//
//  ContentView.swift
//  Scroll
//
//  Created by Adon Omeri on 18/3/2026.
//

import ColorfulX
import Network
import SwiftUI

// MARK: - Adaptive Sheet Modifier

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
	@State private var frameLimit: Int = 120
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

				VStack {
					Spacer()
						.frame(height: 130)

					ScrollPadView(touchLocation: scrollPadViewModel.touchLocation)
						.gesture(scrollDragGesture)
						.accessibilityLabel("Scrolling pad")
						.accessibilityHint("Drag up or down with one finger to scroll your Mac")
						.padding(15)
				}
			}
			.ignoresSafeArea()
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button {
						isConnectionPresented = true
					} label: {
						Label {
							Text("\(connectivityManager.macConnectionStatus.uppercased())")
								.contentTransition(.numericText())
						} icon: {
							if connectivityManager.isConnectedToMac {
								Image(systemName: "macbook")
									.transition(.blurReplace)
							}
						}
						.labelStyle(.titleAndIcon)
						.fontDesign(.monospaced)
						.font(.caption)
						.fixedSize()
						.padding(11)
						.glassEffect(.regular.tint(connectivityManager.isConnectedToMac ? .green : .red).interactive())
						.foregroundStyle(connectivityManager.isConnectedToMac ? .black : .white)
						.animation(.easeInOut, value: connectivityManager.isConnectedToMac)
					}
					.buttonStyle(.plain)
				}
				.sharedBackgroundVisibility(.hidden)
				.matchedTransitionSource(id: "connect", in: namespace)

				ToolbarItem(placement: .topBarTrailing) {
					Button {
						isSettingsPresented = true
					} label: {
						Label("Settings", systemImage: "slider.horizontal.3")
					}
				}
				.matchedTransitionSource(id: "settings", in: namespace)
			}
			.popover(isPresented: $isSettingsPresented) {
				settingsSheet
					.presentationDetents([.fraction(0.6), .large])
					.presentationContentInteraction(.resizes)
					.navigationTransition(
						.zoom(sourceID: "settings", in: namespace)
					)
			}
			.popover(isPresented: $isConnectionPresented) {
				connectView
					.presentationDetents([.fraction(0.7), .large])
					.presentationContentInteraction(.scrolls)
					.navigationTransition(
						.zoom(sourceID: "connect", in: namespace)
					)
			}
			.onAppear {
				syncLocalStateFromDefaults()
				// Give discovery time to find hosts before auto-connecting
				Task {
					try? await Task.sleep(for: .milliseconds(500))
					connectivityManager.checkAutoConnect()
				}
			}
			.alert("Unpaired", isPresented: .init(
				get: { connectivityManager.wasUnpaired },
				set: { if !$0 { connectivityManager.clearUnpairedFlag() } }
			)) {
				Button("OK") { connectivityManager.clearUnpairedFlag() }
			} message: {
				Text("The Mac has removed this device from its paired list.")
			}
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

	@State private var showDeviceNameAlert = false
	@State private var editingDeviceName = ""
	@State private var showForgetAlert = false

	private var settingsSheet: some View {
		NavigationStack {
			Form {
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
		let pairedMac = connectivityManager.lastConnectedMac
		let currentMac = connectivityManager.currentMac
		let isConnected = connectivityManager.isConnectedToMac

		return NavigationStack {
			List {
				Section("This Device") {
					Button {
						editingDeviceName = connectivityManager.deviceName
						showDeviceNameAlert = true
					} label: {
						HStack {
							Label("Name", systemImage: "iphone")
							Spacer()
							Text(connectivityManager.deviceName)
							Image(systemName: "chevron.right")
								.font(.caption)
						}
					}
					.buttonStyle(.plain)
				}

				if isConnected, let current = currentMac {
					Section {
						VStack(alignment: .leading) {
							HStack(alignment: .center) {
								Image(systemName: "macbook")
									.tint(.primary)
									.imageScale(.large)

								VStack(alignment: .leading) {
									Text(current.displayName)
									Text("Connected")
										.font(.caption)
										.foregroundStyle(.green)
								}
							}
							.font(.headline)
							.padding(.bottom, 10)

							HStack {
								Button {
									connectivityManager.disconnect()
								} label: {
									Text("Disconnect")
										.frame(maxWidth: .infinity)
								}
								.buttonStyle(.glass)
								.tint(.blue)

								Button {
									showForgetAlert = true
								} label: {
									Text("Forget")
										.frame(maxWidth: .infinity)
								}
								.buttonStyle(.glassProminent)
								.tint(.red)
							}
						}
					}
					.transition(.opacity)
				}

				if !isConnected {
					Section {
						if connectivityManager.pairingState == .pending {
							ProgressView("Waiting for approval…")
								.foregroundStyle(.orange)

						} else if connectivityManager.pairingState == .rejected {
							Label("Connection rejected by Mac", systemImage: "xmark.circle.fill")
								.foregroundStyle(.red)
						}
					}
					.transition(.opacity)
				}

				Section("Available Macs") {
					if hosts.isEmpty {
						HStack {
							ProgressView()
								.padding(.trailing, 8)
							Text("Searching…")
								.foregroundStyle(.secondary)
						}
					} else {
						ForEach(hosts) { mac in
							let isThisConnected = currentMac?.id == mac.id && isConnected
							let isPaired = mac.deviceInfo?.id == pairedMac?.id

							if !isThisConnected {
								Button {
									withAnimation(.easeInOut) {
										connectivityManager.connectToHost(mac.browseResult)
									}
								} label: {
									HStack {
										VStack(alignment: .leading, spacing: 2) {
											Label(mac.deviceInfo?.name ?? mac.displayName, systemImage: "macbook")
												.font(.body)
											if isPaired {
												Text("Paired")
													.font(.caption)
													.foregroundStyle(.secondary)
											}
										}
										Spacer()
										if connectivityManager.pairingState == .pending && connectivityManager.currentMac?.id == mac.id {
											ProgressView()
												.transition(.blurReplace)
										}
									}
								}
							}
						}
					}
				}
			}
			.animation(.easeInOut, value: isConnected)
			.alert("Forget this Mac?", isPresented: $showForgetAlert) {
				Button("Cancel", role: .cancel) {}
				Button("Forget", role: .destructive) {
					connectivityManager.forgetLastMac()
				}
			} message: {
				Text("This will disconnect and remove the pairing. You'll need to approve the connection again.")
			}
			.alert("Rename Device", isPresented: $showDeviceNameAlert) {
				TextField("Name", text: $editingDeviceName)
				Button("Cancel", role: .cancel) {}
				Button("Save", role: .confirm) {
					let trimmed = editingDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
					if !trimmed.isEmpty {
						connectivityManager.deviceName = trimmed
						connectivityManager.flushIfPending()
						connectivityManager.disconnect()
						connectivityManager.forgetLastMac()
					}
				}
				.keyboardShortcut(.defaultAction)
			} message: {
				Text("This will disconnect and remove the pairing. You'll need to approve the connection again.")
			}
			.toolbar {
				ToolbarItem(placement: .title) {
					Text("Connect to Mac")
						.fontDesign(.monospaced)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						isConnectionPresented = false
					}
				}
			}
		}
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
