import SwiftUI

struct macOSSettingsView: View {
    @AppStorage("compilerPath") private var compilerPath = "/Library/TeX/texbin"

    var body: some View {
        Form {
            TextField("TeXバイナリのフォルダ", text: $compilerPath)
            Text("通常のMacTeXでは /Library/TeX/texbin を使用します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 520)
    }
}
