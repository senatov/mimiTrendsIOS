import AppKit
import SwiftUI

@main
struct ReleaseCompleteWindow: App {
    @State private var isVisible = false
    private let version: String
    private let releaseURL: URL
    private let appIconPath: String
    private let items: [ReleaseItem]

    init() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        version = arguments[safe: 0] ?? ""
        releaseURL = URL(string: arguments[safe: 1] ?? "") ?? URL(fileURLWithPath: "/")
        appIconPath = arguments[safe: 5] ?? ""
        items = [
            ReleaseItem(title: "Installer disk image", detail: arguments[safe: 2] ?? "", symbol: "externaldrive", url: URL(fileURLWithPath: arguments[safe: 2] ?? "/")),
            ReleaseItem(title: "Release notes", detail: arguments[safe: 3] ?? "", symbol: "doc.text", url: URL(fileURLWithPath: arguments[safe: 3] ?? "/")),
            ReleaseItem(title: "Built app", detail: arguments[safe: 4] ?? "", symbol: "app", url: URL(fileURLWithPath: arguments[safe: 4] ?? "/"))
        ]
    }

    var body: some Scene {
        WindowGroup("Release ready") {
            ReleaseSummaryView(version: version, releaseURL: releaseURL, appIconPath: appIconPath, items: items, isVisible: $isVisible)
                .frame(width: 620, height: 570)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
    }
}

private struct ReleaseItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let url: URL
}

private struct ReleaseSummaryView: View {
    let version: String
    let releaseURL: URL
    let appIconPath: String
    let items: [ReleaseItem]
    @Binding var isVisible: Bool
    @State private var iconPulse = false

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Release files").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("Click a file to open it").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ReleaseFileRow(item: item)
                        if index < items.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.07)))
                HStack(spacing: 12) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Published release").font(.system(size: 13, weight: .medium))
                        Text(releaseURL.absoluteString).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Link(destination: releaseURL) {
                        Label("Open", systemImage: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(.blue.opacity(0.09), in: Capsule())
                    }
                }
                .padding(14)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.07)))
            }
            .padding(.horizontal, 30).padding(.top, 23)
            Spacer(minLength: 16)
            HStack {
                Text("Signed, notarized and published").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 30).padding(.bottom, 22)
        }
        .background(LinearGradient(colors: [Color(red: 0.94, green: 0.97, blue: 1), Color(red: 0.97, green: 0.96, blue: 1), Color(red: 0.97, green: 0.98, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear { withAnimation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.12)) { isVisible = true } }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                if let icon = NSImage(contentsOfFile: appIconPath) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 72, height: 72)
                } else {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 35)).foregroundStyle(.blue)
                        .frame(width: 72, height: 72).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
                Image(systemName: "checkmark.circle.fill").font(.system(size: 23)).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green).background(Circle().fill(.white).padding(-2))
                    .scaleEffect(isVisible ? 1 : 0.25).opacity(isVisible ? 1 : 0)
            }
            .scaleEffect(isVisible ? 1 : 0.88)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your release is ready").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("mimiTrends-iOS  \(version)").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                Label("Published successfully", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
            }
            Spacer()
        }
        .padding(.horizontal, 30).padding(.vertical, 25)
        .background(.white.opacity(0.65))
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.06)).frame(height: 1) }
    }
}

private struct ReleaseFileRow: View {
    let item: ReleaseItem

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.blue)
                .frame(width: 38, height: 38).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .semibold))
                Link(item.url.lastPathComponent, destination: item.url)
                    .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .help(item.detail)
            }
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "arrow.up.right.square").font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Show in Finder")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? { indices.contains(index) ? self[index] : nil }
}
