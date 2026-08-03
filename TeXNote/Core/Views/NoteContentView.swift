import SwiftUI

struct NoteContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var workspace: NoteWorkspace

    @State private var selectedCardID: UUID?
    @State private var editingCardID: UUID?
    @State private var newCardID: UUID?
    @State private var isShowingSearch = false
    @State private var isShowingAbout = false
    @State private var isConfirmingDeletion = false

    init(workspace: NoteWorkspace) {
        self.workspace = workspace
        _selectedCardID = State(initialValue: workspace.document.cards.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            noteTitleBar

            Divider()

            if let selectedCard {
                CardDetailView(
                    card: selectedCard,
                    canSelectNextCard: canSelectNextCard,
                    canSelectPreviousCard: canSelectPreviousCard,
                    editAction: {
                        editingCardID = selectedCard.id
                    },
                    addRelatedAction: addRelatedCard,
                    deleteAction: {
                        isConfirmingDeletion = true
                    },
                    nextCardAction: selectNextCard,
                    previousCardAction: selectPreviousCard
                )
                .id(selectedCard.id)
            } else {
                ContentUnavailableView {
                    Label("Cardがありません", systemImage: "rectangle.stack")
                } actions: {
                    Button("新しいCard", systemImage: "square.and.pencil") {
                        addCard()
                    }
                }
            }
        }
        .noteWorkspacePresentation(
            workspace: workspace,
            editingCardID: $editingCardID,
            newCardID: $newCardID
        )
        .sheet(isPresented: $isShowingSearch) {
            CardSearchView(cards: workspace.document.cards) { cardID in
                selectedCardID = cardID
            }
        }
        .alert("About TeXNote", isPresented: $isShowingAbout) {
            Button("OK") {}
        } message: {
            Text("TeXで記述できるCardをまとめ、Packageとして持ち運べるノートアプリです。")
        }
        .alert("Cardを削除しますか？", isPresented: $isConfirmingDeletion) {
            Button("削除", role: .destructive) {
                deleteSelectedCard()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            if let selectedCard {
                Text("「\(selectedCard.title)」を削除します。この操作は取り消せません。")
            }
        }
        .onAppear {
            selectAvailableCard()
        }
        .onChange(of: workspace.document.id) {
            selectedCardID = workspace.document.cards.first?.id
        }
        .onChange(of: workspace.document.cards.map(\.id)) {
            selectAvailableCard()
        }
        .onChange(of: workspace.noteName) {
            workspace.noteNameDidChange()
        }
    }

    private var noteTitleBar: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(spacing: 8) {
                    noteNameField
                    noteToolbarButtons
                }
            } else {
                ZStack {
                    noteNameField
                    noteToolbarButtons
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var noteNameField: some View {
        TextField("Note名", text: $workspace.noteName)
            .textFieldStyle(.plain)
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var noteToolbarButtons: some View {
        HStack(spacing: 14) {
            Spacer()

            Button("検索", systemImage: "magnifyingglass") {
                isShowingSearch = true
            }

            Button("新しいCard", systemImage: "square.and.pencil") {
                addCard()
            }

            Button("最新のCard", systemImage: "house") {
                selectLatestCard()
            }

            noteMenu
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private var noteMenu: some View {
        Menu {
            Group {
                Button("新しいNote", systemImage: "doc.badge.plus") {
                    workspace.requestNewNote()
                }

                Button("開く…", systemImage: "square.and.arrow.down") {
                    workspace.requestOpen()
                }

                Button("保存", systemImage: "square.and.arrow.up") {
                    workspace.requestSave()
                }

                Button(
                    "名前をつけて保存…",
                    systemImage: "square.and.arrow.up.on.square"
                ) {
                    workspace.requestSaveAs()
                }

                Divider()

                Button("About TeXNote", systemImage: "info.circle") {
                    isShowingAbout = true
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("メニュー")
        }
    }

    private var selectedCard: TeXCard? {
        guard let selectedCardID else { return nil }
        return workspace.document.cards.first { $0.id == selectedCardID }
    }

    private var selectedIndex: Int? {
        guard let selectedCardID else { return nil }
        return workspace.document.cards.firstIndex { $0.id == selectedCardID }
    }

    private var canSelectNextCard: Bool {
        guard let index = selectedIndex else { return false }
        return workspace.document.cards.indices.contains(index + 1)
    }

    private var canSelectPreviousCard: Bool {
        guard let index = selectedIndex else { return false }
        return index > 0
    }

    private func selectAvailableCard() {
        if let selectedCardID,
           workspace.document.cards.contains(where: { $0.id == selectedCardID }) {
            return
        }
        selectedCardID = workspace.document.cards.first?.id
    }

    private func addCard() {
        let card = TeXCard()
        workspace.document.cards.append(card)
        selectedCardID = card.id
        newCardID = card.id
        editingCardID = card.id
    }

    private func addRelatedCard() {
        let card = TeXCard(title: "関連記事")
        let insertionIndex = selectedIndex.map { $0 + 1 }
            ?? workspace.document.cards.endIndex
        workspace.document.cards.insert(card, at: insertionIndex)
        selectedCardID = card.id
        newCardID = card.id
        editingCardID = card.id
    }

    private func deleteSelectedCard() {
        guard let index = selectedIndex else { return }
        workspace.document.cards.remove(at: index)
        if workspace.document.cards.isEmpty {
            selectedCardID = nil
        } else {
            selectedCardID = workspace.document.cards[
                min(index, workspace.document.cards.count - 1)
            ].id
        }
        workspace.documentDidChange()
    }

    private func selectLatestCard() {
        let latestCard = workspace.document.cards
            .compactMap { card in
                card.lastTypesetAt.map { (card.id, $0) }
            }
            .max { $0.1 < $1.1 }
        guard let latestCard else { return }
        selectedCardID = latestCard.0
    }

    private func selectNextCard() {
        guard let index = selectedIndex,
              workspace.document.cards.indices.contains(index + 1) else {
            return
        }
        selectedCardID = workspace.document.cards[index + 1].id
    }

    private func selectPreviousCard() {
        guard let index = selectedIndex, index > 0 else { return }
        selectedCardID = workspace.document.cards[index - 1].id
    }
}
