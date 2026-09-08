import SwiftUI
import UIKit

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
        GeometryReader { geometry in
            panel(in: geometry.size)
                .frame(maxWidth: min(420, geometry.size.width - 24))
                .position(
                    x: geometry.size.width / 2,
                    y: min(150, geometry.size.height / 2)
                )
                .offset(offset)
        }
    }

    private func panel(in size: CGSize) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Text("検索と置換")
                    .font(.headline)
                Spacer()
                Button("閉じる", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: size))

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
                previousSearchButton
                nextSearchButton
                Spacer()
                (Text("\(currentMatchIndex) / \(matchCount) ") + Text("件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        }
        .shadow(radius: 8, y: 3)
    }

    private var replaceButton: some View {
        Button("置換", action: replaceCurrent)
            .disabled(!searchEnabled || matchCount == 0)
            .contextMenu {
                Button("すべて置換", action: replaceAll)
            }
            .accessibilityHint("長押しですべて置換")
    }

    @ViewBuilder
    private var previousSearchButton: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            Button("前を検索", systemImage: "chevron.up", action: selectPrevious)
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .disabled(!searchEnabled || matchCount == 0)
        } else {
            Button("前を検索", systemImage: "chevron.up", action: selectPrevious)
                .labelStyle(.titleOnly)
                .disabled(!searchEnabled || matchCount == 0)
        }
    }

    @ViewBuilder
    private var nextSearchButton: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            Button("次を検索", systemImage: "chevron.down", action: selectNext)
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .disabled(!searchEnabled || matchCount == 0)
        } else {
            Button("次を検索", systemImage: "chevron.down", action: selectNext)
                .labelStyle(.titleOnly)
                .disabled(!searchEnabled || matchCount == 0)
        }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                )
                offset = CGSize(
                    width: min(max(proposed.width, -size.width / 2 + 70), size.width / 2 - 70),
                    height: min(max(proposed.height, -100), max(0, size.height - 200))
                )
            }
            .onEnded { _ in dragStart = offset }
    }
}
