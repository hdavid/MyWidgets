import SwiftUI

/// A label-and-field pair that stacks on a phone.
///
/// The settings forms were laid out for a 620pt Mac window, where a fixed label
/// column keeps the fields aligned. On a ~390pt iPhone the same fixed widths
/// push the fields off both edges, so there the label goes above instead.
/// `horizontalSizeClass` is `.regular` on macOS and iPad, `.compact` on iPhone
/// portrait, which is exactly the distinction wanted.
struct LabeledField<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var title: String
    var width: CGFloat = 78
    @ViewBuilder var content: () -> Content

    private var stacked: Bool { sizeClass == .compact }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 3) {
                label
                content()
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                label.frame(width: width, alignment: .leading)
                content()
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Caps a control's width on roomy layouts but lets it fill a narrow one,
    /// instead of a hard `frame(width:)` that overflows a phone.
    func settingsWidth(_ w: CGFloat) -> some View {
        frame(maxWidth: w)
    }
}
