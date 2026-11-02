import SwiftUI

/// Caps content width at ~500pt on regular-width devices (iPad) and centers it.
struct AdaptiveContent: ViewModifier {
    @Environment(\.horizontalSizeClass) private var h

    func body(content: Content) -> some View {
        if h == .regular {
            content
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func adaptiveWidth() -> some View {
        modifier(AdaptiveContent())
    }
}