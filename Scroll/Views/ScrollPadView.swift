import SwiftUI

struct ScrollPadView: View {
    let touchLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
				ConcentricRectangle(corners: .concentric(), isUniform: true)
                    .fill(.thinMaterial)
                    .overlay {
						ConcentricRectangle(corners: .concentric(), isUniform: true)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }

       

                ReactiveHorizontalLinesView(size: size, touchLocation: touchLocation)
					.padding(.vertical, 30)
            }
        }
    }
}

private struct ReactiveHorizontalLinesView: View {
    let size: CGSize
    let touchLocation: CGPoint?

    private let lineSpacing: CGFloat = 18

    var body: some View {
        Canvas { context, canvasSize in
            let strokeColor = Color.white.opacity(0.68)
            let lineCount = Int(canvasSize.height / lineSpacing)

            for index in 0...max(lineCount, 0) {
                let y = CGFloat(index) * lineSpacing + 8
                let influence = influenceForLine(atY: y)

                let lineWidth = 1.0 + (influence * 10.0)
                let horizontalInset = 10.0 + ((1.0 - 0) * 26.0)

                var path = Path()
                path.move(to: CGPoint(x: horizontalInset, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width - horizontalInset, y: y))

                context.stroke(
                    path,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            }
        }
        .drawingGroup()
    }

    private func influenceForLine(atY y: CGFloat) -> CGFloat {
        guard let touchLocation else { return 0.1 }

        let distanceY = abs(y - touchLocation.y)
        let influenceRadius = min(size.width, size.height) * 0.55
        let normalized = max(0, 1 - (distanceY / influenceRadius))
        return pow(normalized, 2)
    }
}
