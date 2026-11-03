import SwiftUI

/// Circular avatar: shows the user's profile photo if set, otherwise a system icon.
struct ProfileImageView: View {
    let imageData: Data?
    let size: CGFloat
    var fallbackIcon: String = "person.circle.fill"
    var fallbackColor: Color = .green
    var showBorder: Bool = true

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .background(Circle().fill(Color(.systemGray5)))
        .overlay(
            Circle()
                .stroke(showBorder ? .white : .clear, lineWidth: showBorder ? 2 : 0)
        )
        .shadow(radius: showBorder ? 1 : 0)
    }
}