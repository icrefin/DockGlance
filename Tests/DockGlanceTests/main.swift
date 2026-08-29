import CoreGraphics
import Foundation
import DockGlanceCore

/// Minimal assertion harness: XCTest is not available with this toolchain,
/// so the core-logic tests run as a plain executable.
private func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL"): \(name)")
    if !condition { exitCode = 1 }
}

nonisolated(unsafe) var exitCode: Int32 = 0

let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
let size = CGSize(width: 300, height: 76)

// Dock edge detection.
let visibleBottom = CGRect(x: 0, y: 90, width: 1728, height: 1022)
check(
    "bottom dock detected",
    DockPosition.edge(screenFrame: screen, visibleFrame: visibleBottom) == .bottom
)
let visibleLeft = CGRect(x: 90, y: 0, width: 1638, height: 1092)
check(
    "left dock detected",
    DockPosition.edge(screenFrame: screen, visibleFrame: visibleLeft) == .left)
let visibleRight = CGRect(x: 0, y: 0, width: 1638, height: 1092)
check(
    "right dock detected",
    DockPosition.edge(screenFrame: screen, visibleFrame: visibleRight) == .right)
let visibleTop = CGRect(x: 0, y: 0, width: 1728, height: 1022)
check(
    "top dock detected",
    DockPosition.edge(screenFrame: screen, visibleFrame: visibleTop) == .top)

// Band frames for a bottom dock: the window occupies the dock's strip.
let first = DockPosition.frame(
    screenFrame: screen, visibleFrame: visibleBottom,
    placement: .first, windowSize: size, margin: 8)
let second = DockPosition.frame(
    screenFrame: screen, visibleFrame: visibleBottom,
    placement: .second, windowSize: size, margin: 8)
check("bottom first x", first.minX == 8)
check("bottom first y (in dock band)", first.minY == 0)
check("bottom-first height = dock thickness", first.height == 90)
check("bottom second maxX", second.maxX == screen.maxX - 8)
check("bottom second y (in dock band)", second.minY == 0)

// The same band math for the other three edges.
let top = DockPosition.frame(
    screenFrame: screen, visibleFrame: visibleTop,
    placement: .first, windowSize: size, margin: 8)
check("top dock: widget sits in top band", top.maxY == screen.maxY)
check("top dock: height = band thickness", top.height == 95)
check("top dock: x from left", top.minX == 8)
let left = DockPosition.frame(
    screenFrame: screen, visibleFrame: visibleLeft,
    placement: .first, windowSize: size, margin: 8)
check("left dock: widget spans dock", left.height == size.height)
check("left dock: flush to screen", left.minX == 0)
let right = DockPosition.frame(
    screenFrame: screen, visibleFrame: visibleRight,
    placement: .first, windowSize: size, margin: 8)
check("right dock: widget spans dock", right.height == size.height)
check("right dock: flush to right", right.maxX == screen.maxX)

// Placement order per edge.
check("first is bottom-left for bottom dock",
      Placement.first.corner(for: .bottom) == .bottomLeft)
check("second is bottom-right for bottom dock",
      Placement.second.corner(for: .bottom) == .bottomRight)
check("first is top-left for left dock",
      Placement.first.corner(for: .left) == .topLeft)
check("second is bottom-left for left dock",
      Placement.second.corner(for: .left) == .bottomLeft)
check("first is top-right for right dock",
      Placement.first.corner(for: .right) == .topRight)
check("second is bottom-right for right dock",
      Placement.second.corner(for: .right) == .bottomRight)

// Card distribution between the two ends of the dock band. A 1728-wide
// screen with a 328-wide centered dock leaves 700 pt on each side; each
// card takes 96 pt + 6 spacing with 8 pt padding at both ends.
let slot = (cardWidth: CGFloat(96), spacing: CGFloat(6), endPadding: CGFloat(8))
let dockFrame = CGRect(x: 700, y: 0, width: 328, height: 90)
let bottom = DockEdge.bottom

func split(_ count: Int) -> Int {
    DockPosition.splitCards(
        count: count,
        cardWidth: slot.cardWidth,
        spacing: slot.spacing,
        endPadding: slot.endPadding,
        screenFrame: screen,
        dockFrame: dockFrame,
        edge: bottom,
        margin: 8
    )
}

check("6 cards fit on the left of a 700 pt gap", split(6) == 6)
check("7 cards spill to the right", split(7) == 6)
check("10 cards split 6 left / 4 right", split(10) == 6)
check("0 cards stay empty", split(0) == 0)

// Without a dock frame the band reserves a conservative central dock zone
// (each side is 30% of 1728 = 518 pt): 4 cards fit on a side.
func splitFallback(_ count: Int) -> Int {
    DockPosition.splitCards(
        count: count,
        cardWidth: slot.cardWidth,
        spacing: slot.spacing,
        endPadding: slot.endPadding,
        screenFrame: screen,
        dockFrame: nil,
        edge: bottom,
        margin: 8
    )
}
check("fallback fits 4 on the left", splitFallback(4) == 4)
check("fallback reserves the dock zone", splitFallback(10) == 4)
check("fallback skips empty", splitFallback(0) == 0)

// Clock text formats.
var comps = DateComponents()
comps.year = 2026
comps.month = 8
comps.day = 8
comps.hour = 14
comps.minute = 30
let noon = Calendar.current.date(from: comps)!
check("time is HH:MM", ClockText.time(noon) == "14:30")
check("date is 'Aug 8' style", ClockText.date(noon) == "Aug 8")
check("weekday is short name", ClockText.weekday(noon) == "Sat")

// SMC C struct must be exactly 80 bytes to match the kernel struct.
check("SMC key struct is 80 bytes", SMC.keyDataSize == 80)

// Top-process monitors read local system state.
let tops = ProcessMonitor().sample()
check("top CPU process parsed", tops.cpu.first?.name.isEmpty == false)
check("top CPU value positive", (tops.cpu.first?.value ?? 0) > 0)
check("top memory value positive", (tops.memory.first?.value ?? 0) > 0)

// Byte formatting.
check("0 bytes", ByteFormat.bytes(0) == "0.0 B")
check("1 KB", ByteFormat.bytes(1023) == "1.0 KB")
check("1.2 MB", ByteFormat.bytes(1_234_567) == "1.2 MB")
check("5 GB", ByteFormat.bytes(UInt64(5_000_000_000)) == "5.0 GB")
check("rate K", ByteFormat.rate(12_345) == "12.3 K")
check("rate M", ByteFormat.rate(25_000_000) == "25.0 M")

// Public-IP location for the card: dedupes equal city/country, joins
// distinct ones, and degrades to "—" when nothing is known.
func makeIP(city: String, country: String) -> PublicIPInfo {
    PublicIPInfo(
        ip: "1.2.3.4", type: "IPv4", flagEmoji: "🇸🇬",
        country: country, region: "Central", city: city,
        postal: "123456", isp: "ISP", org: "Org", asn: "AS1",
        timezone: "UTC"
    )
}
check(
    "ip location dedupes equal city/country",
    makeIP(city: "Singapore", country: "Singapore").location == "Singapore"
)
check(
    "ip location joins distinct city/country",
    makeIP(city: "Hangzhou", country: "China").location == "Hangzhou, China"
)
check(
    "ip location country only",
    makeIP(city: "—", country: "Japan").location == "Japan"
)
check("ip location unavailable", PublicIPInfo.unavailable.location == "—")

exit(exitCode)