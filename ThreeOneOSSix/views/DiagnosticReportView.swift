import SwiftUI

/// Assembles a diagnostic report (device header + arbitrary sections) and
/// presents it through the shared paginated reader. Long-operation screens
/// (migration progress/resume) push this with their own sections; the log
/// viewer links to it for the full session report.
struct DiagnosticReportView: View {
    var titleKey: String = "diagnostics.title"
    /// Ordered sections: (heading, body). Heading is appended as "── … ──".
    let sections: [(heading: String, body: String)]

    private var composed: String {
        var lines: [String] = []
        lines.append("3106 Diagnostics")
        lines.append("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) — \(AppInfo.machineName)")
        lines.append("Generated: \(Date())")
        lines.append("Backend: \(SandboxAccess.backend.displayName)")
        for (heading, body) in sections {
            lines.append("")
            lines.append("── \(heading) ──")
            lines.append(body)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        PaginatedTextView(text: composed, titleKey: titleKey)
    }
}
