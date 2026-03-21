//
//  PairingStatusView.swift
//  Scroll
//
//  Created by Adon Omeri on 21/3/2026.
//

import SwiftUI
import Combine

struct PairingStatusView: View {
	let isConnected: Bool
	let currentMac: DiscoveredMac?
	let pairingState: DiscoveredMac.PairingState
	let onDisconnect: () -> Void
	let onForget: () -> Void
	
	@State private var keyboardVisible = false

	var body: some View {
		ZStack {
			if isConnected, let current = currentMac {
				GroupBox {
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

							Spacer()
						}
						.font(.headline)

						HStack {
							Button { onDisconnect() } label: { Text("Disconnect") }
								.buttonStyle(.glass)
								.tint(.blue)

							Spacer()

							Button { onForget() } label: { Text("Forget") }
								.buttonStyle(.glassProminent)
								.tint(.red)
						}
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: 30))
				.containerShape(.rect(cornerRadius: 30))
				.transition(.blurReplace)

			} else if pairingState == .pending || pairingState == .rejected {
				GroupBox {
					HStack(alignment: .center, spacing: 10) {
						if pairingState == .pending {
							Image(systemName: "progress.indicator")
								.symbolEffect(.rotate.byLayer, options: .repeat(.continuous))
								.transition(.blurReplace)
						} else {
							Image(systemName: "xmark.circle")
								.transition(.blurReplace)
						}

						Text(pairingState == .pending ? "Waiting for approval..." : "Connection rejected from Mac")
							.contentTransition(.numericText())

						Spacer()
					}
					.foregroundStyle(pairingState == .pending ? .orange : .red)
				}
				.clipShape(RoundedRectangle(cornerRadius: 30))
				.containerShape(.rect(cornerRadius: 30))
				.transition(.blurReplace)
			}
		}
		.onReceive(Publishers.keyboardShowing) { keyboardVisible = $0 }
		.padding(.bottom, keyboardVisible ? 16 : 0)
		.animation(.snappy, value: keyboardVisible)
		.animation(.easeInOut, value: isConnected)
		.animation(.easeInOut, value: pairingState)
	}
}

extension Publishers {
	static var keyboardShowing: AnyPublisher<Bool, Never> {
		let show = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).map { _ in true }
		let hide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).map { _ in false }
		return MergeMany(show, hide).eraseToAnyPublisher()
	}
}
