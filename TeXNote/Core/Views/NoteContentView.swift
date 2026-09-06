import SwiftUI

struct NoteContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var workspace: NoteWorkspace
    @ObservedObject var authenticationSession: RemoteAuthenticationSession
    private let settingsAction: (() -> Void)?
    private let showsAuthenticationInSidebar: Bool
    private let extendsDetailIntoTopSafeArea: Bool
    private let detailTopSafeAreaInset: CGFloat

    @State private var selectedCardID: UUID?
    @State private var editingCardID: UUID?
    @State private var newCardID: UUID?
    @State private var isShowingSearch = false
    @State private var isShowingAbout = false
    @State private var isConfirmingDeletion = false
    @State private var isShowingAccountUsage = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    init(
        workspace: NoteWorkspace,
        authenticationSession: RemoteAuthenticationSession,
        settingsAction: (() -> Void)? = nil,
        showsAuthenticationInSidebar: Bool = false,
        initialCompactColumn: NavigationSplitViewColumn = .sidebar,
        extendsDetailIntoTopSafeArea: Bool = false,
        detailTopSafeAreaInset: CGFloat = 0
    ) {
        self.workspace = workspace
        self.authenticationSession = authenticationSession
        self.settingsAction = settingsAction
        self.showsAuthenticationInSidebar = showsAuthenticationInSidebar
        self.extendsDetailIntoTopSafeArea = extendsDetailIntoTopSafeArea
        self.detailTopSafeAreaInset = detailTopSafeAreaInset
        _selectedCardID = State(initialValue: workspace.document.cards.first?.id)
        _preferredCompactColumn = State(initialValue: initialCompactColumn)
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: $splitViewVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            cardSidebar
        } detail: {
            cardDetail
                .modifier(
                    PlatformDetailNavigationChromeModifier(
                        dismissSidebar: hideSidebar
                    )
                )
                .padding(
                    .top,
                    extendsDetailIntoTopSafeArea ? detailTopSafeAreaInset : 0
                )
                .ignoresSafeArea(
                    .container,
                    edges: extendsDetailIntoTopSafeArea ? .top : []
                )
        }
        .navigationSplitViewStyle(.balanced)
        .noteWorkspacePresentation(
            workspace: workspace,
            editingCardID: $editingCardID,
            newCardID: $newCardID,
            showsCardTitleField: false
        )
        .sheet(isPresented: $isShowingSearch) {
            CardSearchView(cards: workspace.document.cards) { cardID in
                selectedCardID = cardID
            }
        }
        .sheet(isPresented: $isShowingAbout) {
            TeXNoteAboutView()
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
        .alert("現在の利用状況", isPresented: $isShowingAccountUsage) {
            Button("OK") {}
        } message: {
            if let account = authenticationSession.account {
                Text(
                    "\(account.email)\n\n"
                        + "プラン：\(account.plan.displayName)\n"
                        + "今月：\(account.used) / \(account.limit)回"
                )
            }
        }
        .onAppear {
            selectAvailableCard()
            showDetailInCompactWidth()
        }
        .onChange(of: workspace.document.id) {
            selectedCardID = workspace.document.cards.first?.id
            showDetailInCompactWidth()
        }
        .onChange(of: workspace.document.cards.map(\.id)) {
            selectAvailableCard()
        }
        .onChange(of: workspace.noteName) {
            workspace.noteNameDidChange()
        }
        .onChange(of: workspace.importedCardID) {
            guard let cardID = workspace.importedCardID else { return }
            selectedCardID = cardID
            editingCardID = cardID
            workspace.consumeImportedCardID()
        }
        .task {
            guard showsAuthenticationInSidebar else { return }
            await authenticationSession.refresh()
        }
    }

    @ViewBuilder
    private var cardSidebar: some View {
        if showsAuthenticationInSidebar {
            cardList
                .modifier(
                    PlatformAuthenticationSidebarToolbarModifier {
                        authenticationButton
                    }
                )
                .modifier(PlatformSidebarNavigationChromeModifier())
                .navigationSplitViewColumnWidth(
                    min: 300,
                    ideal: 300,
                    max: 300
                )
        } else {
            cardList
                .modifier(PlatformSidebarNavigationChromeModifier())
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: 240,
                    max: 320
                )
        }
    }

    private var cardList: some View {
        List(selection: $selectedCardID) {
            ForEach(workspace.document.cards) { card in
                Text(card.title)
                    .tag(card.id)
            }
            .onMove(perform: moveCards)
        }
    }

    @ViewBuilder
    private var authenticationButton: some View {
        switch authenticationSession.state {
        case .checking:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("ログイン状態を確認中")
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .fixedSize()
            .background(
                Color.accentColor.opacity(0.10),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
            .accessibilityLabel("ログイン状態を確認中")
        case .signedIn(let account):
            Button {
                isShowingAccountUsage = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.fill")
                    Text("\(account.plan.displayName)でログイン中")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .fixedSize()
                .background(
                    Color.accentColor.opacity(0.10),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            Color.accentColor.opacity(0.45),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
        case .signedOut, .failed:
            Button {
                settingsAction?()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.badge.key.fill")
                    Text("ログイン")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .fixedSize()
                .background(
                    Color.accentColor.opacity(0.10),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            Color.accentColor.opacity(0.45),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(settingsAction == nil)
        }
    }

    private var cardDetail: some View {
        VStack(spacing: 0) {
            noteTitleBar

            Divider()

            if let selectedCardBinding {
                CardDetailView(
                    card: selectedCardBinding,
                    editsTitle: true,
                    titleChanged: {
                        workspace.documentDidChange()
                    },
                    canSelectNextCard: canSelectNextCard,
                    canSelectPreviousCard: canSelectPreviousCard,
                    editAction: {
                        editingCardID = selectedCardBinding.wrappedValue.id
                    },
                    exportAction: {
                        workspace.requestCardExport(
                            cardID: selectedCardBinding.wrappedValue.id
                        )
                    },
                    deleteAction: {
                        isConfirmingDeletion = true
                    },
                    nextCardAction: selectNextCard,
                    previousCardAction: selectPreviousCard
                )
                .id(selectedCardBinding.wrappedValue.id)
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
        HStack {
            if splitViewVisibility == .detailOnly {
                PlatformSidebarRevealControl {
                    showSidebar()
                }
            }

            Spacer()

            noteActionControls
        }
    }

    @ViewBuilder
    private var noteActionControls: some View {
        if PlatformNoteActionChrome.usesGroupedChrome {
            PlatformNoteActionGroup {
                noteActionControlItems
            }
        } else {
            noteActionControlItems
                .buttonStyle(.borderless)
        }
    }

    private var noteActionControlItems: some View {
        HStack(spacing: PlatformNoteActionChrome.usesGroupedChrome ? 4 : 14) {
            Button("検索", systemImage: "magnifyingglass") {
                isShowingSearch = true
            }
            .platformNoteActionControl()

            Button("新しいCard", systemImage: "square.and.pencil") {
                addCard()
            }
            .platformNoteActionControl()

            Button(
                "最新のCard",
                systemImage: PlatformNoteActionSymbols.latestCard
            ) {
                selectLatestCard()
            }
            .platformNoteActionControl()

            noteMenu
        }
        .labelStyle(.iconOnly)
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

                Button(
                    "TeX文書のインポート…",
                    systemImage: "square.and.arrow.down"
                ) {
                    workspace.requestTeXDocumentImport(
                        insertingAfter: selectedCardID
                    )
                }

                if let settingsAction {
                    Divider()

                    Button("版組サーバー設定", systemImage: "server.rack") {
                        settingsAction()
                    }
                }

                Divider()

                Button("TeXNoteについて", systemImage: "info.circle") {
                    isShowingAbout = true
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: PlatformNoteActionSymbols.menu)
                .accessibilityLabel("メニュー")
        }
        .platformNoteActionControl()
    }

    private var selectedCard: TeXCard? {
        guard let selectedCardID else { return nil }
        return workspace.document.cards.first { $0.id == selectedCardID }
    }

    private var selectedCardBinding: Binding<TeXCard>? {
        guard let index = selectedIndex else { return nil }
        return $workspace.document.cards[index]
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

    private func showDetailInCompactWidth() {
        guard horizontalSizeClass == .compact else { return }
        preferredCompactColumn = .detail
    }

    private func showSidebar() {
        withAnimation {
            splitViewVisibility = .all
        }
    }

    private func hideSidebar() {
        guard splitViewVisibility != .detailOnly else { return }
        withAnimation {
            splitViewVisibility = .detailOnly
        }
    }

    private func addCard() {
        let card = TeXCard()
        workspace.document.cards.append(card)
        selectedCardID = card.id
        newCardID = card.id
        editingCardID = card.id
    }

    private func moveCards(
        from source: IndexSet,
        to destination: Int
    ) {
        workspace.document.cards.move(
            fromOffsets: source,
            toOffset: destination
        )
        workspace.documentDidChange()
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

extension View {
    @ViewBuilder
    func platformNoteActionControl() -> some View {
        if PlatformNoteActionChrome.usesGroupedChrome {
            modifier(PlatformNoteActionControlModifier())
        } else {
            self
        }
    }
}
