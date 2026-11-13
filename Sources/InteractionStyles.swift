import SwiftUI
import AppKit

// Native, restrained interactions. Haptics respect the user's preference.
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

// A single button treatment across the library, editor, and settings.
struct TactileGlassActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CLIPButtonFace(label: configuration.label,
                       pressed: configuration.isPressed,
                       prominent: prominent)
    }
}

private struct CLIPButtonFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let prominent: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    private let accent = Color(red: 0.67, green: 0.78, blue: 0.87)

    var body: some View {
        label
            .foregroundStyle(prominent ? Color(red: 0.10, green: 0.13, blue: 0.16) : Color.white.opacity(0.91))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent
                          ? (pressed ? accent.opacity(0.79) : accent)
                          : Color.white.opacity(pressed ? 0.15 : hovered ? 0.115 : 0.075))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Color.white.opacity(0.09), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.38)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { hovered = $0 }
            .onChange(of: pressed) { _, down in
                if down && isEnabled { CLIPFeedback.tap() }
            }
    }
}

struct TactileSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

struct TactileClipCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CLIPCardFace(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct CLIPCardFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovered = false

    var body: some View {
        label
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(hovered ? 0.24 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(pressed ? 0.83 : 1)
            .onHover { hovered = $0 }
    }
}

struct TactileSegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

struct TactileTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CLIPTextFace(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct CLIPTextFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovered = false

    var body: some View {
        label
            .foregroundStyle(hovered ? Color.white : Color(red: 0.67, green: 0.78, blue: 0.87))
            .underline(hovered)
            .opacity(pressed ? 0.7 : 1)
            .onHover { hovered = $0 }
    }
}
