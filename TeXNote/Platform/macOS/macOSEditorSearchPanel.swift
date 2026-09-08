import SwiftUI

struct PlatformEditorSearchPanel: View {
    @Binding var searchText: String
    @Binding var replacementText: String
    @Binding var isCaseSensitive: Bool
    @Binding var wrapsSearch: Bool
    let currentMatchIndex: Int
    let matchCount: Int
    let searchEnabled: Bool
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    let replaceCurrent: () -> Void
    let replaceAll: () -> Void
    let close: () -> Void

    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Text("検索と置換")
                    .font(.headline)
                Spacer()
                Button("閉じる", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)

            HStack(spacing: 6) {
                Button {
                    isCaseSensitive.toggle()
                } label: {
                    Text(isCaseSensitive ? "Aa" : "aa")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonBorderShape(.circle)
                .tint(isCaseSensitive ? Color.accentColor : Color.secondary)
                .accessibilityLabel("大文字と小文字を区別")
                Toggle("循環", isOn: $wrapsSearch)
                    .toggleStyle(.button)
                    .tint(wrapsSearch ? Color.accentColor : Color.secondary)
                    .accessibilityLabel("検索結果を循環")
                Spacer()
                Button("前を検索", systemImage: "chevron.up", action: selectPrevious)
                    .labelStyle(.titleAndIcon)
                    .disabled(!searchEnabled || matchCount == 0)
                Button("次を検索", systemImage: "chevron.down", action: selectNext)
                    .labelStyle(.titleAndIcon)
                    .disabled(!searchEnabled || matchCount == 0)
                Spacer()
                (Text("\(currentMatchIndex) / \(matchCount) ") + Text("件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .trailing)
            }

            HStack(spacing: 6) {
                TextField("文字列検索", text: $searchText)
                if !searchText.isEmpty {
                    Button("検索をクリア", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                TextField("置換文字列", text: $replacementText)
                replaceButton
            }
        }
        .textFieldStyle(.roundedBorder)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(10)
        .frame(width: 510)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        }
        .shadow(radius: 8, y: 3)
        .offset(offset)
    }

    private var replaceButton: some View {
        Button("置換", action: replaceCurrent)
            .disabled(!searchEnabled || matchCount == 0)
            .contextMenu {
                Button("すべて置換", action: replaceAll)
            }
            .accessibilityHint("長押しですべて置換")
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
            }
            .onEnded { _ in dragStart = offset }
    }
}
