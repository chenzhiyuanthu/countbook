import XCTest
@testable import Countbook

/*
 * The chart geometry exists twice — `web/src/ui/charts.tsx` and
 * `ios/Countbook/Design/Charts.swift` — and nothing in either build would
 * notice the two drifting apart, because both would still draw something.
 * Every expectation below is the literal output of the TypeScript for the same
 * input, taken from the cases DESIGN.md §7.9 names as required: empty input,
 * a single element, all zero, a negative deviation larger than any positive, a
 * day exactly equal to the standard, a 28- and a 31-day month, the ±0.5
 * quantisation cases, and a subscription list with two segments under the
 * minimum.
 *
 * The values are compared exactly, not within a tolerance. Both platforms
 * quantise through the same `q4`, and a q4 result is a correctly rounded
 * IEEE-754 division of an integer by 10000, so the two doubles are bit-equal or
 * the port is wrong.
 */

private func bar(
    _ x: Double, _ w: Double, _ underY: Double, _ underH: Double, _ overY: Double, _ overH: Double
) -> StripBar {
    StripBar(x: x, w: w, underY: underY, underH: underH, overY: overY, overH: overH)
}

private func span(_ i: Int, _ x0: Double, _ x1: Double, _ over: Bool) -> ChartSpan {
    ChartSpan(i: i, x0: x0, x1: x1, over: over)
}

final class ChartGeometryTests: XCTestCase {

    // MARK: - q4

    /// `Math.round(-0.5)` is `-0` in JavaScript and `-1` in Swift. Both
    /// implementations route around it the same way; this is the assertion that
    /// says so.
    func testQ4RoundsHalfAwayFromZeroOnBothSigns() {
        XCTAssertEqual(q4(0.00005), 0.0001)
        XCTAssertEqual(q4(-0.00005), -0.0001)
        XCTAssertEqual(q4(0.00015), 0.0001)   // 1.5 → 2 in decimal, but 0.00015 is below its half in binary
        XCTAssertEqual(q4(-0.00015), -0.0001)
        XCTAssertEqual(q4(0.123449), 0.1234)
        XCTAssertEqual(q4(-0.123451), -0.1235)
        XCTAssertEqual(q4(1.0 / 3.0), 0.3333)
        XCTAssertEqual(q4(-2.0 / 3.0), -0.6667)
        XCTAssertEqual(q4(0), 0)
    }

    /// −0 and 0 must be the same coordinate; a sign on a zero-length mark would
    /// be a difference the drawing cannot express.
    func testQ4NegativeZeroIsZero() {
        XCTAssertEqual(q4(-0.0), 0)
    }

    // MARK: - deviationLayout

    func testDeviationEmpty() {
        XCTAssertEqual(deviationLayout([]), [])
    }

    func testDeviationSingleTouchesItsEdge() {
        XCTAssertEqual(deviationLayout([12_345]), [span(0, 0.5, 1, true)])
        XCTAssertEqual(deviationLayout([-12_345]), [span(0, 0, 0.5, false)])
    }

    /// Zero is not over, and draws nothing: x0 == x1 at the rule.
    func testDeviationAllZero() {
        XCTAssertEqual(
            deviationLayout([0, 0, 0]),
            [span(0, 0.5, 0.5, false), span(1, 0.5, 0.5, false), span(2, 0.5, 0.5, false)]
        )
    }

    /// The scale is symmetric and shared: a −¥1000 sets the extent, so the
    /// largest over bar stops well short of the right edge.
    func testDeviationNegativeLargerThanAnyPositive() {
        XCTAssertEqual(
            deviationLayout([-100_000, 25_000, -3, 0, 50_000]),
            [
                span(0, 0, 0.5, false),
                span(1, 0.5, 0.625, true),
                span(2, 0.4938, 0.5, false),
                span(3, 0.5, 0.5, false),
                span(4, 0.5, 0.75, true),
            ]
        )
    }

    func testDeviationMixed() {
        XCTAssertEqual(
            deviationLayout([68_800, -21_000, 1_200, 0, -450]),
            [
                span(0, 0.5, 1, true),
                span(1, 0.3474, 0.5, false),
                span(2, 0.5, 0.5087, true),
                span(3, 0.5, 0.5, false),
                span(4, 0.4938, 0.5, false),
            ]
        )
    }

    /// A non-zero delta never disappears: below the 2pt floor it is drawn at the
    /// floor. Both edges land on a .5 quantum, which is the rounding case.
    func testDeviationMinimumBarFloor() {
        XCTAssertEqual(
            deviationLayout([1_000_000, 1, -1]),
            [span(0, 0.5, 1, true), span(1, 0.5, 0.5063, true), span(2, 0.4938, 0.5, false)]
        )
    }

    // MARK: - monthStripLayout

    func testStripEmptyStillPlacesTheStandard() {
        let out = monthStripLayout([], 10_000)
        XCTAssertEqual(out.bars, [])
        XCTAssertEqual(out.standardY, 0.375)
    }

    func testStripSingleDay() {
        let out = monthStripLayout([5_000], 10_000)
        XCTAssertEqual(out.bars, [bar(0.2, 0.6, 0.6875, 0.3125, 0.6875, 0)])
        XCTAssertEqual(out.standardY, 0.375)
    }

    /// No standard set: every bar is entirely over, and the reference sits on
    /// the baseline rather than dividing by zero.
    func testStripWithoutAStandard() {
        let out = monthStripLayout([1_000, 0, 3_000], 0)
        XCTAssertEqual(
            out.bars,
            [
                bar(0.0667, 0.2, 1, 0, 0.6667, 0.3333),
                bar(0.4, 0.2, 1, 0, 1, 0),
                bar(0.7333, 0.2, 1, 0, 0, 1),
            ]
        )
        XCTAssertEqual(out.standardY, 1)
    }

    func testStripAllZero() {
        let out = monthStripLayout([0, 0, 0, 0], 0)
        XCTAssertEqual(
            out.bars,
            [
                bar(0.05, 0.15, 1, 0, 1, 0),
                bar(0.3, 0.15, 1, 0, 1, 0),
                bar(0.55, 0.15, 1, 0, 1, 0),
                bar(0.8, 0.15, 1, 0, 1, 0),
            ]
        )
        XCTAssertEqual(out.standardY, 1)
    }

    /// A day exactly equal to the standard is under it — the comparison is
    /// strict — so its over piece has zero height and no hatch is drawn.
    func testStripDayEqualToStandardIsUnder() {
        let out = monthStripLayout([10_000, 10_000, 20_000], 10_000)
        XCTAssertEqual(
            out.bars,
            [
                bar(0.0667, 0.2, 0.5, 0.5, 0.5, 0),
                bar(0.4, 0.2, 0.5, 0.5, 0.5, 0),
                bar(0.7333, 0.2, 0.5, 0.5, 0, 0.5),
            ]
        )
        XCTAssertEqual(out.standardY, 0.5)
        XCTAssertEqual(out.bars[0].overH, 0)
        XCTAssertEqual(out.bars[1].overH, 0)
    }

    func testStrip28DayMonth() {
        let out = monthStripLayout((0..<28).map { $0 * 500 }, 6_000)
        XCTAssertEqual(out.bars.count, 28)
        XCTAssertEqual(out.standardY, 0.5556)
        XCTAssertEqual(
            out.bars,
            [
                bar(0.0071, 0.0214, 1, 0, 1, 0),
                bar(0.0429, 0.0214, 0.963, 0.037, 0.963, 0),
                bar(0.0786, 0.0214, 0.9259, 0.0741, 0.9259, 0),
                bar(0.1143, 0.0214, 0.8889, 0.1111, 0.8889, 0),
                bar(0.15, 0.0214, 0.8519, 0.1481, 0.8519, 0),
                bar(0.1857, 0.0214, 0.8148, 0.1852, 0.8148, 0),
                bar(0.2214, 0.0214, 0.7778, 0.2222, 0.7778, 0),
                bar(0.2571, 0.0214, 0.7407, 0.2593, 0.7407, 0),
                bar(0.2929, 0.0214, 0.7037, 0.2963, 0.7037, 0),
                bar(0.3286, 0.0214, 0.6667, 0.3333, 0.6667, 0),
                bar(0.3643, 0.0214, 0.6296, 0.3704, 0.6296, 0),
                bar(0.4, 0.0214, 0.5926, 0.4074, 0.5926, 0),
                bar(0.4357, 0.0214, 0.5556, 0.4444, 0.5556, 0),
                bar(0.4714, 0.0214, 0.5556, 0.4444, 0.5185, 0.037),
                bar(0.5071, 0.0214, 0.5556, 0.4444, 0.4815, 0.0741),
                bar(0.5429, 0.0214, 0.5556, 0.4444, 0.4444, 0.1111),
                bar(0.5786, 0.0214, 0.5556, 0.4444, 0.4074, 0.1481),
                bar(0.6143, 0.0214, 0.5556, 0.4444, 0.3704, 0.1852),
                bar(0.65, 0.0214, 0.5556, 0.4444, 0.3333, 0.2222),
                bar(0.6857, 0.0214, 0.5556, 0.4444, 0.2963, 0.2593),
                bar(0.7214, 0.0214, 0.5556, 0.4444, 0.2593, 0.2963),
                bar(0.7571, 0.0214, 0.5556, 0.4444, 0.2222, 0.3333),
                bar(0.7929, 0.0214, 0.5556, 0.4444, 0.1852, 0.3704),
                bar(0.8286, 0.0214, 0.5556, 0.4444, 0.1481, 0.4074),
                bar(0.8643, 0.0214, 0.5556, 0.4444, 0.1111, 0.4444),
                bar(0.9, 0.0214, 0.5556, 0.4444, 0.0741, 0.4815),
                bar(0.9357, 0.0214, 0.5556, 0.4444, 0.037, 0.5185),
                bar(0.9714, 0.0214, 0.5556, 0.4444, 0, 0.5556),
            ]
        )
    }

    func testStrip31DayMonth() {
        let out = monthStripLayout((0..<31).map { $0 % 7 == 0 ? 30_000 : 4_000 }, 8_000)
        XCTAssertEqual(out.bars.count, 31)
        XCTAssertEqual(out.standardY, 0.7333)
        XCTAssertEqual(
            out.bars,
            [
                bar(0.0065, 0.0194, 0.7333, 0.2667, 0, 0.7333),
                bar(0.0387, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.071, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.1032, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.1355, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.1677, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.2, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.2323, 0.0194, 0.7333, 0.2667, 0, 0.7333),
                bar(0.2645, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.2968, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.329, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.3613, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.3935, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.4258, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.4581, 0.0194, 0.7333, 0.2667, 0, 0.7333),
                bar(0.4903, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.5226, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.5548, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.5871, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.6194, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.6516, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.6839, 0.0194, 0.7333, 0.2667, 0, 0.7333),
                bar(0.7161, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.7484, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.7806, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.8129, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.8452, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.8774, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.9097, 0.0194, 0.7333, 0.2667, 0, 0.7333),
                bar(0.9419, 0.0194, 0.8667, 0.1333, 0.8667, 0),
                bar(0.9742, 0.0194, 0.8667, 0.1333, 0.8667, 0),
            ]
        )
    }

    // MARK: - regret blocks

    /// `floor((320 + 3) / (8 + 3))`, the width the phone column gives.
    func testRegretColumnCount() {
        let cols = max(
            ChartGeom.regretMinCols,
            Int(((ChartGeom.plotW + ChartGeom.regretGap) / (ChartGeom.regretUnit + ChartGeom.regretGap)).rounded(.down))
        )
        XCTAssertEqual(cols, 29)
    }

    func testSpreadMarksIsEvenNotClustered() {
        XCTAssertEqual(spreadMarks(40, 9).sorted(), [2, 6, 11, 15, 20, 24, 28, 33, 37])
    }

    func testSpreadMarksDegenerateInputs() {
        XCTAssertEqual(spreadMarks(30, 0), [])
        XCTAssertEqual(spreadMarks(0, 5), [])
        XCTAssertEqual(spreadMarks(7, 7).sorted(), [0, 1, 2, 3, 4, 5, 6])
        // More marks than cells cannot mark more cells than there are.
        XCTAssertEqual(spreadMarks(5, 9).sorted(), [0, 1, 2, 3, 4])
    }

    func testRegretBlockWraps() {
        let cells = regretBlockLayout(34, spreadMarks(34, 4), 29)
        XCTAssertEqual(cells.count, 34)
        XCTAssertEqual(cells[0], RegretCell(col: 0, row: 0, bad: false))
        XCTAssertEqual(cells[4], RegretCell(col: 4, row: 0, bad: true))
        XCTAssertEqual(cells[12], RegretCell(col: 12, row: 0, bad: true))
        XCTAssertEqual(cells[21], RegretCell(col: 21, row: 0, bad: true))
        XCTAssertEqual(cells[28], RegretCell(col: 28, row: 0, bad: false))
        XCTAssertEqual(cells[29], RegretCell(col: 0, row: 1, bad: true))
        XCTAssertEqual(cells[33], RegretCell(col: 4, row: 1, bad: false))
        XCTAssertEqual(cells.filter(\.bad).count, 4)
    }

    func testRegretBlockEmpty() {
        XCTAssertEqual(regretBlockLayout(0, [], 29), [])
    }

    // MARK: - annual bar

    func testAnnualEmptyAndAllZero() {
        XCTAssertEqual(annualBarSegments([]), [])
        XCTAssertEqual(
            annualBarSegments([0, 0]),
            [AnnualSegment(x0: 0, x1: 0), AnnualSegment(x0: 0, x1: 0)]
        )
    }

    func testAnnualSingleFillsTheBar() {
        XCTAssertEqual(annualBarSegments([12_000]), [AnnualSegment(x0: 0, x1: 1)])
    }

    func testAnnualSegmentsAreContiguous() {
        XCTAssertEqual(
            annualBarSegments([120_000, 60_000, 20_000]),
            [
                AnnualSegment(x0: 0, x1: 0.6),
                AnnualSegment(x0: 0.6, x1: 0.9),
                AnnualSegment(x0: 0.9, x1: 1),
            ]
        )
    }

    /// Two rows fall under `total × 3 / 320` and are summed into one 其他; the
    /// bar is then laid out over the merged list, not the original.
    func testAnnualBelowMinimumSegmentsMergeIntoOne() {
        let annual: [Fen] = [120_000, 60_000, 300, 200]
        let total = annual.reduce(0) { $0 + max(0, $1) }
        let floor = Double(total) * Double(ChartGeom.annualMinSegment / ChartGeom.plotW)
        XCTAssertEqual(floor, 1692.1875)

        let kept = annual.filter { Double($0) >= floor }
        let rest = annual.filter { Double($0) < floor }.reduce(0, +)
        XCTAssertEqual(kept, [120_000, 60_000])
        XCTAssertEqual(rest, 500)

        XCTAssertEqual(
            annualBarSegments(kept + [rest]),
            [
                AnnualSegment(x0: 0, x1: 0.6648),
                AnnualSegment(x0: 0.6648, x1: 0.9972),
                AnnualSegment(x0: 0.9972, x1: 1),
            ]
        )
    }

    // MARK: - hour scatter

    func testHourScatterEmptyAndAllZero() {
        XCTAssertEqual(hourScatterLayout([], ChartGeom.hourMaxRows), [])
        XCTAssertEqual(hourScatterLayout([0, 0, 0], ChartGeom.hourMaxRows), [])
    }

    /// A column taller than the cap stops at the cap; the remainder is printed
    /// as `+n` rather than stacked off the plot.
    func testHourScatterClipsAtMaxRows() {
        XCTAssertEqual(
            hourScatterLayout([1, 0, 13, 3], ChartGeom.hourMaxRows),
            [ScatterDot(col: 0, row: 0)]
                + (0..<10).map { ScatterDot(col: 2, row: $0) }
                + (0..<3).map { ScatterDot(col: 3, row: $0) }
        )
    }

    func testHourScatterFullDay() {
        let counts = (0..<24).map { $0 == 23 ? 4 : ($0 % 6 == 0 ? 2 : 0) }
        let dots = hourScatterLayout(counts, ChartGeom.hourMaxRows)
        XCTAssertEqual(dots.count, 12)
        XCTAssertEqual(dots.first, ScatterDot(col: 0, row: 0))
        XCTAssertEqual(dots.last, ScatterDot(col: 23, row: 3))
    }
}
