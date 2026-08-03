import SwiftUI

struct TeXNoteAboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "Unknown"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image("AboutAppIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 120, height: 120)
                .padding(.bottom, 8)

            Text("TeXNote")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)

            Divider()

            Text("""
カード単位でTeX文書を編集・組版し、
PDFと一緒に整理できるノートアプリです。
""")
            .multilineTextAlignment(.center)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("カード単位のTeX編集", systemImage: "rectangle.stack")
                Label("複数のTeXエンジンに対応", systemImage: "gearshape.2")
                Label("PDFプレビュー", systemImage: "doc.richtext")
                Label("ノート内の全文検索", systemImage: "magnifyingglass")
                Label("画像・スタイルファイルの管理", systemImage: "folder")
                Label("macOS・iPad・iPhoneで利用可能", systemImage: "macbook.and.iphone")
            }

            Divider()

            Link(
                "GitHub Repository",
                destination: URL(string: "https://github.com/smat1957/TeXNote")!
            )

            Text("""
Copyright © 2026
Shusei Matoike
""")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 420)
    }
}

#Preview {
    TeXNoteAboutView()
}
