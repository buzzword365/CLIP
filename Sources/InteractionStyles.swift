import SwiftUI
import AppKit

// Respect macOS haptic preferences; no sounds or artificial delays.
enum CLIPFeedback {
    @MainActor static func tap() {
        guard UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    @MainActor static func detent() {
        guard UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// One coherent tactile style for primary buttons, icon actions and glass pills.
struct TactileGlassActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonFace(label: configuration.label,
                        pressed: configuration.isPressed,
                        prominent: prominent)
    }
}

private struct GlassButtonFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let prominent: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                label
                    .foregroundStyle(prominent ? Color(red: 0.07, green: 0.11, blue: 0.18) : .white)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 11)
                    .glassEffect(prominent
                        ? .regular.tint(Color(red: 0.53, green: 0.76, blue: 1).opacity(0.96)).interactive()
                        : .regular.interactive(), in: Capsule())
            } else {
                label
                    .foregroundStyle(prominent ? .black : .white)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 11)
                    .background(prominent
                        ? Color(red: 0.53, green: 0.76, blue: 1)
                        : Color.white.opacity(0.14), in: Capsule())
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [
                        .white.opacity(hovered ? 0.45 : 0.23),
                        .white.opacity(0.07),
                        .white.opacity(hovered ? 0.22 : 0.09)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.85)
                .allowsHitTesting(false)
        }
        .brightness(hovered && isEnabled ? 0.035 : 0)
        .shadow(color: .black.opacity(isEnabled ? (hovered ? 0.23 : 0.10) : 0),
                radius: hovered ? 12 : 5, x: 0, y: hovered ? 5 : 2)
        .scaleEffect(!isEnabled || reduceMotion ? 1 : pressed ? 0.955 : hovered ? 1.028 : 1)
        .offset(y: !isEnabled || reduceMotion ? 0 : pressed ? 1.5 : hovered ? -0.5 : 0)
        .opacity(isEnabled ? 1 : 0.38)
        .contentShape(Capsule())
        .animation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.66),
                   value: pressed)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.16), value: hovered)
        .onHover { hovered = $0 }
        .onChange(of: pressed) { _, down in
            if down && isEnabled { CLIPFeedback.tap() }
        }
    }
}

struct TactileSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TactilePlainFace(label: configuration.label,
                         pressed: configuration.isPressed,
                         variant: .sidebar)
    }
}

struct TactileClipCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TactilePlainFace(label: configuration.label,
                         pressed: configuration.isPressed,
                         variant: .card)
    }
}

struct TactileSegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TactilePlainFace(label: configuration.label,
                         pressed: configuration.isPressed,
                         variant: .segment)
    }
}

private enum TactileVariant {
    case sidebar, card, segment
}

private struct TactilePlainFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let variant: TactileVariant
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .background {
                if hovered && variant == .sidebar {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.047))
                }
            }
            .overlay {
                if hovered && variant == .card {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .brightness(hovered && isEnabled ? 0.028 : 0)
            .scaleEffect(!isEnabled || reduceMotion ? 1 :
                         pressed ? (variant == .card ? 0.985 : 0.952) :
                         hovered ? (variant == .card ? 1.011 : 1.018) : 1)
            .offset(y: reduceMotion || !isEnabled ? 0 : pressed ? 1 : hovered && variant == .card ? -1 : 0)
            .shadow(color: variant == .card && hovered ? .black.opacity(0.23) : .clear,
                    radius: 10, y: 5)
            .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.71),
                       value: pressed)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.15), value: hovered)
            .onHover { hovered = $0 }
            .onChange(of: pressed) { _, down in
                if down && isEnabled { CLIPFeedback.tap() }
            }
    }
}

struct TactileTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TactileTextFace(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct TactileTextFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .foregroundStyle(hovered ? Color.white : Color(red: 0.60, green: 0.81, blue: 1))
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .underline(hovered, color: .white.opacity(0.7))
            .scaleEffect(reduceMotion ? 1 : pressed ? 0.97 : 1)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.13), value: hovered)
            .onHover { hovered = $0 }
            .onChange(of: pressed) { _, down in
                if down { CLIPFeedback.tap() }
            }
    }
}
