import SwiftUI

/// Drag right past threshold (60pt) to trigger reply with haptic feedback.
/// Works on iPhone, iPad, all iOS versions. No visual indicator — just the gesture.
struct SwipeToReply: ViewModifier {
    let onReply: () -> Void
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .offset(x: max(0, offset))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let dx = value.translation.width
                        if dx > 0 {
                            withAnimation(.interactiveSpring()) {
                                offset = min(dx * 0.7, threshold * 1.5)
                            }
                        }
                    }
                    .onEnded { value in
                        if offset >= threshold {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onReply()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = 0
                        }
                    }
            )
    }
}

extension View {
    func swipeToReply(onReply: @escaping () -> Void) -> some View {
        modifier(SwipeToReply(onReply: onReply))
    }
}