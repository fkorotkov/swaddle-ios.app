import SwiftUI

extension EnvironmentValues {
    @Entry var careWideLayout = false
}

/// The decision belongs to the content's proposal, not a device or fold angle.
struct AdaptiveCarePage<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth = 320
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        GeometryReader { geometry in
            let wide = sizeClass == .regular && !typeSize.isAccessibilitySize
                && geometry.size.width >= minimumColumnWidth * 2 + 68
            content(wide)
                .environment(\.careWideLayout, wide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Keep chart and selection identities stable while their positions change.
struct CareChartColumns<Plot: View, Detail: View>: View {
    var readoutFirstWhenCompact = false
    var showsPlot = true
    @ViewBuilder var plot: Plot
    @ViewBuilder var detail: Detail
    @Environment(\.careWideLayout) private var wide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CareChartLayout(wide: wide && showsPlot, readoutFirstWhenCompact: readoutFirstWhenCompact,
                        spacing: showsPlot ? 24 : 0) {
            VStack(alignment: .leading, spacing: 18) { plot }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) { detail }.frame(maxWidth: .infinity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: wide)
    }
}

private struct CareChartLayout: Layout {
    let wide: Bool
    let readoutFirstWhenCompact: Bool
    let spacing: CGFloat

    private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> [CGSize] {
        let width = proposal.width ?? 640
        let detailWidth = wide ? max(240, (width - spacing) * 0.34) : width
        let plotWidth = wide ? max(0, width - spacing - detailWidth) : width
        return [subviews[0].sizeThatFits(.init(width: plotWidth, height: nil)),
                subviews[1].sizeThatFits(.init(width: detailWidth, height: nil))]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(proposal, subviews)
        return CGSize(width: proposal.width ?? 640,
                      height: wide ? max(sizes[0].height, sizes[1].height)
                        : sizes[0].height + spacing + sizes[1].height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(.init(width: bounds.width, height: nil), subviews)
        let detailWidth = wide ? max(240, (bounds.width - spacing) * 0.34) : bounds.width
        let plotWidth = wide ? bounds.width - spacing - detailWidth : bounds.width
        let plotY = !wide && readoutFirstWhenCompact ? sizes[1].height + spacing : 0
        let detailY = !wide && !readoutFirstWhenCompact ? sizes[0].height + spacing : 0
        // SwiftUI mirrors the layout's logical coordinates in right-to-left locales.
        subviews[0].place(at: .init(x: bounds.minX, y: bounds.minY + plotY), anchor: .topLeading,
                          proposal: .init(width: plotWidth, height: sizes[0].height))
        subviews[1].place(at: .init(x: wide ? bounds.maxX - detailWidth : bounds.minX,
                                  y: bounds.minY + detailY), anchor: .topLeading,
                          proposal: .init(width: detailWidth, height: sizes[1].height))
    }
}
