import SwiftUI

extension View {
    /// The rounded, grouped-background container used for content cards.
    func cardStyle(padding: CGFloat = 20, cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
