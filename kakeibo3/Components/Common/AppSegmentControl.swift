import SwiftUI

struct AppSegmentControl: View {
    let items: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    var width: CGFloat = SegmentBarLayout.standard.width

    @AppStorage(AppColors.themeColorStorageKey)
    private var themeHex: String = AppColors.defaultThemeHex

    private var segmentLayout: SegmentBarLayout { SegmentBarLayout.standard }

    private var itemWidth: CGFloat {
        (width - segmentLayout.innerPadding * 2) / CGFloat(items.count)
    }

    private var selectedOffset: CGFloat {
        CGFloat(selectedIndex) * itemWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(segmentLayout.backgroundColor)

            Capsule()
                .fill(segmentLayout.selectedBackgroundColor)
                .frame(width: itemWidth, height: segmentLayout.selectedHeight)
                .padding(segmentLayout.innerPadding)
                .offset(x: selectedOffset)
                .animation(.easeInOut(duration: 0.22), value: selectedIndex)

            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    Button {
                        onSelect(index)
                    } label: {
                        Text(items[index])
                            .font(segmentLayout.font)
                            .foregroundStyle(
                                selectedIndex == index
                                ? segmentLayout.textColor
                                : Color.gray.opacity(0.6)
                            )
                            .frame(width: itemWidth)
                            .frame(height: segmentLayout.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: width, height: segmentLayout.height)
        .contentShape(Rectangle())
    }
}
