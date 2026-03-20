import SwiftUI

struct ScrollPadView: View {
    let touchLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.gray.opacity(0.22))
                    .padding(10)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.gray.opacity(0.26))
                    .padding(20)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .padding(30)

                ReactiveHorizontalLinesView(size: size, touchLocation: touchLocation)
                    .padding(30)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 22, y: 14)
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
            let centerX = canvasSize.width / 2

            for index in 0...max(lineCount, 0) {
                let y = CGFloat(index) * lineSpacing + 8
                let influence = influenceForLine(atY: y)

                let lineWidth = 1.0 + (influence * 5.0)
                let horizontalInset = 10.0 + ((1.0 - influence) * 26.0)

                var path = Path()
                path.move(to: CGPoint(x: horizontalInset, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width - horizontalInset, y: y))

                context.stroke(
                    path,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                // Subtle center pulse for depth.
                let pulseRadius = 0.8 + (influence * 2.2)
                let pulseRect = CGRect(
                    x: centerX - pulseRadius,
                    y: y - pulseRadius,
                    width: pulseRadius * 2,
                    height: pulseRadius * 2
                )
                context.fill(Path(ellipseIn: pulseRect), with: .color(strokeColor.opacity(0.8)))
            }
        }
        .drawingGroup()
    }

    private func influenceForLine(atY y: CGFloat) -> CGFloat {
        guard let touchLocation else { return 0.1 }

        let distanceY = abs(y - touchLocation.y)
        let influenceRadius = min(size.width, size.height) * 0.55
        let normalized = max(0, 1 - (distanceY / influenceRadius))
        return pow(normalized, 1.9)
    }
}
