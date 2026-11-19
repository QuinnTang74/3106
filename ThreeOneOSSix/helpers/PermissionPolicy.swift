import Foundation

/// POSIX mode formatting and the preset ladder offered by the file-info
/// permission editor.
///
/// Kept free of SwiftUI so the formatting rules can be tested: an octal/symbolic
/// mismatch would show the user one mode and write another.
enum PermissionPolicy {
    /// Ordered least-to-most permissive; the UI renders them in this order.
    static let presets: [Int] = [0o444, 0o555, 0o644, 0o755]

    static func masked(_ mode: Int) -> Int { mode & 0o777 }

    /// Four digits, matching what `ls -l`-style tools and the editor both show.
    static func octalString(_ mode: Int) -> String {
        String(format: "%04o", masked(mode))
    }

    /// `rwxr-xr-x`. The leading file-type character is deliberately omitted:
    /// this view already reports file vs folder separately, and a hardcoded
    /// `-` would be wrong for directories.
    static func symbolicString(_ mode: Int) -> String {
        let bits = masked(mode)
        var out = ""
        for shift in [6, 3, 0] {
            let group = (bits >> shift) & 0o7
            out += (group & 0o4) != 0 ? "r" : "-"
            out += (group & 0o2) != 0 ? "w" : "-"
            out += (group & 0o1) != 0 ? "x" : "-"
        }
        return out
    }

    /// True when no write bit is set for any of owner/group/other.
    static func isReadOnly(_ mode: Int) -> Bool {
        masked(mode) & 0o222 == 0
    }

    /// A preset is offered-but-disabled when the file already has that mode.
    static func isCurrent(_ mode: Int, preset: Int) -> Bool {
        masked(mode) == masked(preset)
    }

    /// Compact label for a preset button: octal plus the symbolic form. Both
    /// halves are format-derived rather than prose, so the row needs no
    /// translation and cannot drift from the mode it will actually write.
    static func presetLabel(_ preset: Int) -> String {
        "\(octalString(preset)) · \(symbolicString(preset))"
    }
}