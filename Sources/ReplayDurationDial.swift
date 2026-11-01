import SwiftUI

// A thermostat-style replay control. The bottom 90° is intentionally inactive,
// leaving a physical "knob" sweep of 270° with seven fixed recording durations.
struct ReplayDurationDial: View {
    @Binding var seconds: Int
    private let options = [15, 30, 60, 120, 180, 300, 600]
    private let size: CGFloat = 206
    private let center: CGFloat = 103
    private let startAngle = 135.0
    private let sweepAngle = 270.0
    private let accent = Color(red: 0.53, green: 0.76, blue: 1)
    @State private var isDragging = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int {
        options.firstIndex(of: seconds) ?? 1
    }

    private var fraction: Double {
        Double(index) / Double(options.count - 1)
    }

    private var currentAngle: Double {
        startAngle + sweepAngle * fraction
    }

    private func point(angle: Double, radius: CGFloat) -> CGPoint {
        let radians = CGFloat(angle * .pi / 180)
        return CGPoint(x: center + radius * cos(radians),
                       y: center + radius * sin(radians))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.027))
                .frame(width: 156, height: 156)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.085), lineWidth: 1)
                }

            DialArc(fraction: 1)
                .stroke(.white.opacity(0.13),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: size, height: size)

            DialArc(fraction: fraction)
                .stroke(AngularGradient(
                    colors: [accent.opacity(0.45), accent, .init(red: 0.70, green: 0.64, blue: 1)],
                    center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .shadow(color: accent.opacity(0.35), radius: 8)
                .frame(width: size, height: size)

            ForEach(0..<49, id: \.self) { tick in
                let angle = startAngle + sweepAngle * Double(tick) / 48
                let position = point(angle: angle, radius: tick.isMultiple(of: 8) ? 77 : 79)
                Capsule()
                    .fill(tick <= index * 8 ? accent.opacity(0.82) : .white.opacity(0.24))
                    .frame(width: tick.isMultiple(of: 8) ? 2 : 1,
                           height: tick.isMultiple(of: 8) ? 11 : 5)
                    .rotationEffect(.degrees(angle + 90))
                    .position(position)
            }

            let knob = point(angle: currentAngle, radius: 91)
            Circle()
                .fill(.white)
                .frame(width: isDragging ? 19 : hovering ? 17 : 15,
                       height: isDragging ? 19 : hovering ? 17 : 15)
                .shadow(color: accent.opacity(isDragging ? 0.85 : 0.45),
                        radius: isDragging ? 16 : 10)
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(0.45), lineWidth: 2)
                }
                .position(knob)

            VStack(spacing: 0) {
                Text("REPLAY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.bottom, 4)
                Text(seconds < 60 ? "\(seconds)" : "\(seconds / 60)")
                    .font(.system(size: 47, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(0.96))
                Text(seconds < 60 ? "SECONDS" : "MINUTES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.51))
                    .padding(.top, -2)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(accent.opacity(0.7))
                    .padding(.top, 12)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    let dx = gesture.location.x - center
                    let dy = gesture.location.y - center
                    let r = hypot(dx, dy)
                    guard r > 60 && r < 120 else { return }
                    isDragging = true
                    update(from: gesture.location)
                }
                .onEnded { _ in isDragging = false }
        )
        .onHover { hovering = $0 }
        .animation(reduceMotion ? .none : .spring(response: 0.18, dampingFraction: 0.68),
                   value: isDragging)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.16), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Replay duration")
        .accessibilityValue(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) minutes")
        .accessibilityHint("Drag around the dial to adjust how much recent footage is saved.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                seconds = options[min(index + 1, options.count - 1)]
            case .decrement:
                seconds = options[max(index - 1, 0)]
            @unknown default:
                break
            }
        }
    }

    private func update(from location: CGPoint) {
        let x = location.x - center
        let y = location.y - center
        let distance = hypot(x, y)
        guard distance > 60 && distance < 120 else { return }
        var angle = (atan2(Double(y), Double(x)) * 180 / .pi + 360)
            .truncatingRemainder(dividingBy: 360)
        // Do NOT jump from minimum to maximum across the inactive bottom arc.
        guard angle >= startAngle || angle <= 45 else { return }
        if angle <= 45 { angle += 360 }
        angle = min(405, max(startAngle, angle))
        let progress = (angle - startAngle) / sweepAngle
        let newIndex = min(options.count - 1, max(0,
            Int((progress * Double(options.count - 1)).rounded())))
        let newSeconds = options[newIndex]
        guard newSeconds != seconds else { return }
        CLIPFeedback.detent()
        if reduceMotion {
            seconds = newSeconds
        } else {
            withAnimation(.interactiveSpring(response: 0.20, dampingFraction: 0.80)) {
                seconds = newSeconds
            }
        }
    }
}

private struct DialArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.445
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 160
        for i in 0...steps {
            let angle = CGFloat((135.0 + 270.0 * fraction * Double(i) / Double(steps)) * .pi / 180.0)
            let point = CGPoint(x: center.x + radius * cos(angle),
                                y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        return path
    }
}
