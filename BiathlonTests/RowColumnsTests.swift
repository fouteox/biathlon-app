import SwiftUI
import Testing

@testable import Biathlon

struct RowColumnsTests {
    @Test func staysSideBySideUpToTheLargestStandardSize() {
        #expect(RowColumns(.xxxLarge) == .sideBySide)
        #expect(RowColumns(.xxxLarge).trailingAlignment == .trailing)
    }

    /// HIG Layout: "horizontally adjacent views may need to stack vertically to provide more space for text".
    @Test func stacksFromTheFirstAccessibilitySize() {
        #expect(RowColumns(.accessibility1) == .stacked)
        #expect(RowColumns(.accessibility1).trailingAlignment == .leading)
    }
}
