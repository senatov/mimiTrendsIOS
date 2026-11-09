import AppKit
import SwiftUI

@main
struct InstallerGuide: App {
    var body: some Scene {
        WindowGroup("Install mimiTrends") {
            InstallerGuideView()
                .frame(width: 620, height: 560)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
    }
}

private struct InstallerGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel = false
    @State private var glow = false

    private var diskURL: URL { Bundle.main.bundleURL.deletingLastPathComponent() }
    private var appURL: URL { diskURL.appendingPathComponent("mimiTrends-iOS.app") }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                Group {
                    if let illustration = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/InstallerBackground.png")) {
                        Image(nsImage: illustration).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [Color(red: 0.91, green: 0.96, blue: 1), Color(red: 0.97, green: 0.95, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                HStack {
                    endpoint(icon: appIcon, title: "mimiTrends", tint: .blue)
                    Spacer(minLength: 0)
                    endpoint(icon: applicationsIcon, title: "Applications", tint: .indigo)
                }
                .padding(.horizontal, 38).padding(.top, 17).frame(maxHeight: .infinity, alignment: .top)
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule().fill(.blue.opacity(0.22)).frame(width: 21, height: 4)
                    }
                    Image(systemName: "arrowtriangle.right.fill").font(.system(size: 12)).foregroundStyle(.blue)
                }
                .offset(y: 7)
                Image(systemName: "dog.fill")
                    .font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 43, height: 43).background(.orange.gradient, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .orange.opacity(glow ? 0.34 : 0.12), radius: glow ? 14 : 5, y: 4)
                    .offset(x: travel ? 133 : -133, y: travel ? 48 : 64)
                    .rotationEffect(.degrees(travel ? 9 : -9))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: travel)
            }
            .frame(height: 300)
            .padding(.horizontal, 26).padding(.top, 22)

            Text("Drag mimiTrends-iOS.app to Applications")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .padding(.top, 18)
            Text("Then open mimiTrends from your Applications folder.")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 5)

            Spacer(minLength: 18)
            HStack(spacing: 10) {
                Button { NSWorkspace.shared.open(diskURL) } label: {
                    Label("Show installation window", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                Button { NSWorkspace.shared.activateFileViewerSelecting([appURL]) } label: {
                    Label("Show app", systemImage: "app")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 22)
        }
        .background(LinearGradient(colors: [.white, Color(red: 0.96, green: 0.98, blue: 1)], startPoint: .top, endPoint: .bottom))
        .onAppear {
            guard !reduceMotion else { return }
            travel = true
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private var header: some View {
        HStack(spacing: 15) {
            Image(systemName: "sparkles")
                .font(.system(size: 23, weight: .semibold)).foregroundStyle(.blue)
                .frame(width: 48, height: 48).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("A quick install").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("One simple drag and mimiTrends is ready.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 21)
    }

    private func endpoint(icon: NSImage, title: String, tint: Color) -> some View {
        VStack(spacing: 9) {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: 70, height: 70)
                .padding(8).background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.12)))
                .shadow(color: tint.opacity(0.12), radius: 12, y: 5)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
        }
    }

    private var appIcon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }
    private var applicationsIcon: NSImage { NSWorkspace.shared.icon(forFile: "/Applications") }
}
