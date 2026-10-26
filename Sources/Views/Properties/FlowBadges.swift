import SwiftUI

/// Displays a unit's features as small rounded badges, wrapped in an adaptive grid.
struct FlowBadges: View {
    let features: [UnitFeature]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(features) { feature in
                HStack(spacing: 6) {
                    Image(systemName: feature.systemImage)
                    Text(feature.label)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    FlowBadges(features: [.balcony, .fittedKitchen, .cellar, .parking])
        .padding()
}
