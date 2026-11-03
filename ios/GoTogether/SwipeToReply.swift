import SwiftUI

/// Wraps content with a drag-to-reply gesture. Swipe right past threshold
/// triggers the reply action with haptic feedback — works on iPhone, iPad,
/// and all iOS versions. No visible button.
struct SwipeToReply: ViewModifier {
    let onReply: () -> Void
    @State private var offset: CGFloat = 0
    private let threshold: CGFloat = 60

    func body(content: Content) -> some View {
        content
            .offset(x: max(0, offset))
            .background(
                // Blue indicator peeks from behind as you drag
                HStack {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.leading, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.blue)
                .opacity(min(1.0, offset / threshold))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            )
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Only allow drag to the right
                        let dx = value.translation.width
                        if dx > 0 {
                            withAnimation(.interactiveSpring()) {
                                offset = min(dx * 0.7, threshold * 1.5)
                            }
                        }
                    }
                    .onEnded { value in
                        if offset >= threshold {
                            // Threshold met — trigger reply
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
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