// Reflowing layouts for Dynamic Type through AX5 (SPEC §11 "no truncation", "cards reflow").
//
// These replace `ViewThatFits` and `LazyVGrid` column switches. `ViewThatFits` builds a second copy
// of its content and shows whichever fits, so at some text sizes a label is a different view
// than at others: the accessibility audit reports it as "Dynamic Type font sizes are partially
// unsupported", VoiceOver focus can jump, and the HStack copy can still truncate text it measured
// as fitting. A `Layout` keeps one view per child at every size and only moves it.

import SwiftUI

// MARK: - Flow

/// Lays children out left to right and wraps onto a new line when the next one doesn't fit,
/// like words in a paragraph. A child wider than the line is offered the full width (so text
/// wraps inside it instead of being cut off). Children in a line are centered vertically.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 10, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(width: bounds.width, subviews).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                                       proposal: ProposedViewSize(item.frame.size))
        }
    }

    private func arrange(width: CGFloat?, _ subviews: Subviews) -> (items: [(index: Int, frame: CGRect)], size: CGSize) {
        let maxWidth = width ?? .infinity
        var lines: [[(index: Int, size: CGSize)]] = []
        var lineWidth: CGFloat = 0
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if let last = lines.last, !last.isEmpty, lineWidth + spacing + size.width <= maxWidth {
                lines[lines.count - 1].append((index, size))
                lineWidth += spacing + size.width
            } else {
                lines.append([(index, size)])
                lineWidth = size.width
            }
        }
        var items: [(index: Int, frame: CGRect)] = []
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        for (number, line) in lines.enumerated() {
            if number > 0 { y += lineSpacing }
            let height = line.map(\.size.height).max() ?? 0
            var x: CGFloat = 0
            for (offset, child) in line.enumerated() {
                if offset > 0 { x += spacing }
                items.append((child.index, CGRect(x: x, y: y + (height - child.size.height) / 2,
                                                  width: child.size.width, height: child.size.height)))
                x += child.size.width
            }
            usedWidth = max(usedWidth, x)
            y += height
        }
        return (items, CGSize(width: min(usedWidth, maxWidth), height: y))
    }
}

// MARK: - Label and value

/// Two children: a label on the leading edge and a value on the trailing edge, lined up on their
/// first baselines. When both don't fit on one line, the value goes under the label.
public struct LabelValueLayout: Layout {
    public var minGap: CGFloat
    public var stackedSpacing: CGFloat

    public init(minGap: CGFloat = 12, stackedSpacing: CGFloat = 2) {
        self.minGap = minGap
        self.stackedSpacing = stackedSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(width: bounds.width, subviews).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                                       proposal: ProposedViewSize(item.frame.size))
        }
    }

    private func arrange(width: CGFloat?, _ subviews: Subviews) -> (items: [(index: Int, frame: CGRect)], size: CGSize) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let together = ideal.map(\.width).reduce(0, +) + minGap * CGFloat(max(ideal.count - 1, 0))
        if subviews.count == 2, together <= (width ?? .infinity) {
            let total = width ?? together
            let baselines = subviews.indices.map {
                subviews[$0].dimensions(in: ProposedViewSize(ideal[$0]))[VerticalAlignment.firstTextBaseline]
            }
            let top = baselines.max() ?? 0
            let label = CGRect(x: 0, y: top - baselines[0], width: ideal[0].width, height: ideal[0].height)
            let value = CGRect(x: total - ideal[1].width, y: top - baselines[1], width: ideal[1].width, height: ideal[1].height)
            return ([(0, label), (1, value)], CGSize(width: total, height: max(label.maxY, value.maxY)))
        }
        // Stacked: each child gets the full width and wraps if it needs to.
        let maxWidth = width ?? .infinity
        var items: [(index: Int, frame: CGRect)] = []
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        for index in subviews.indices {
            if index > 0 { y += stackedSpacing }
            let size = ideal[index].width > maxWidth
                ? subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) : ideal[index]
            items.append((index, CGRect(origin: CGPoint(x: 0, y: y), size: size)))
            usedWidth = max(usedWidth, size.width)
            y += size.height
        }
        return (items, CGSize(width: width ?? usedWidth, height: y))
    }
}

// MARK: - Equal columns

/// As many equal columns as fit `minColumnWidth`, at least one; each row is as tall as its
/// tallest child, and every child in a row is offered that height (tiles line up).
/// Pass a `@ScaledMetric` width so the grid drops to fewer columns as the text grows.
public struct ColumnsLayout: Layout {
    public var minColumnWidth: CGFloat
    public var spacing: CGFloat

    public init(minColumnWidth: CGFloat, spacing: CGFloat = 12) {
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(width: bounds.width, subviews).items {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                                       proposal: ProposedViewSize(item.frame.size))
        }
    }

    private func arrange(width: CGFloat?, _ subviews: Subviews) -> (items: [(index: Int, frame: CGRect)], size: CGSize) {
        let total = width ?? minColumnWidth
        let columns = max(1, Int((total + spacing) / (minColumnWidth + spacing)))
        let columnWidth = max(0, (total - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var items: [(index: Int, frame: CGRect)] = []
        var y: CGFloat = 0
        for rowStart in stride(from: 0, to: subviews.count, by: columns) {
            if rowStart > 0 { y += spacing }
            let row = rowStart..<min(rowStart + columns, subviews.count)
            let height = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
            for index in row {
                let column = CGFloat(index - rowStart)
                items.append((index, CGRect(x: column * (columnWidth + spacing), y: y, width: columnWidth, height: height)))
            }
            y += height
        }
        return (items, CGSize(width: total, height: y))
    }
}
