import Testing
import MiniRules

struct TextStyleTests {
    @Test func opaqueRGBConvertsToRoundedOKLCH() {
        #expect(TextStyle.oklch(fromComputedColor: "rgb(0, 0, 0)") == "oklch(0 0 0)")
        #expect(TextStyle.oklch(fromComputedColor: "rgb(255, 255, 255)") == "oklch(1 0 0)")
        #expect(TextStyle.oklch(fromComputedColor: "rgb(255, 0, 0)") == "oklch(0.63 0.26 29)")
        #expect(TextStyle.oklch(fromComputedColor: "rgb(0, 0, 255)") == "oklch(0.45 0.31 264)")
    }

    @Test func alphaAppearsOnlyBelowOne() {
        #expect(TextStyle.oklch(fromComputedColor: "rgba(0, 0, 0, 0.5)") == "oklch(0 0 0 / 0.5)")
        #expect(TextStyle.oklch(fromComputedColor: "rgba(255, 255, 255, 1)") == "oklch(1 0 0)")
        #expect(TextStyle.oklch(fromComputedColor: "rgb(0 0 0 / 0.25)") == "oklch(0 0 0 / 0.25)")
    }

    @Test func unparsableColorsAreRejected() {
        #expect(TextStyle.oklch(fromComputedColor: "color(srgb 1 0 0)") == nil)
        #expect(TextStyle.oklch(fromComputedColor: "rgb(300, 0, 0)") == nil)
        #expect(TextStyle.oklch(fromComputedColor: "rgb(1, 2)") == nil)
        #expect(TextStyle.oklch(fromComputedColor: "") == nil)
    }

    @Test func fontFamilyKeepsTheWholeStack() {
        #expect(TextStyle.fontFamilyStack("\"Helvetica Neue\",  Arial,\n sans-serif") == "\"Helvetica Neue\", Arial, sans-serif")
    }

    @Test func blockListsDeclarationsAndSkipsTransformNone() {
        let style = ComputedTextStyle(
            fontFamily: "Inter, system-ui, sans-serif", fontSize: "15px", lineHeight: "24px", fontWeight: "500",
            letterSpacing: "-0.15px", color: "rgb(0, 0, 0)", textTransform: "none")
        #expect(TextStyle.block(style) == """
        font-family: Inter, system-ui, sans-serif;
        font-size: 15px;
        line-height: 24px;
        font-weight: 500;
        letter-spacing: -0.15px;
        color: oklch(0 0 0);
        """)
    }

    @Test func blockIncludesTransformWhenSet() {
        let style = ComputedTextStyle(
            fontFamily: "serif", fontSize: "12px", lineHeight: "normal", fontWeight: "700",
            letterSpacing: "normal", color: "rgba(0, 0, 0, 0.5)", textTransform: "uppercase")
        let text = TextStyle.block(style)
        #expect(text?.hasSuffix("color: oklch(0 0 0 / 0.5);\ntext-transform: uppercase;") == true)
        #expect(text?.contains("line-height: normal;") == true)
    }

    @Test func blockIsNilForAnUnreadableColor() {
        let style = ComputedTextStyle(
            fontFamily: "serif", fontSize: "12px", lineHeight: "normal", fontWeight: "400",
            letterSpacing: "normal", color: "nonsense", textTransform: "none")
        #expect(TextStyle.block(style) == nil)
    }
}
