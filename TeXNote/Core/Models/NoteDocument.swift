import Foundation

struct NoteDocument: Codable, Sendable {
    var formatVersion = 6
    var id: UUID
    var name: String
    var cards: [TeXCard]
    var createdAt: Date
    var updatedAt: Date

    static var starter: NoteDocument {
        NoteDocument(name: "名称未設定", cards: [TeXCard(title: "最初のカード")])
    }

    init(
        id: UUID = UUID(),
        name: String,
        cards: [TeXCard],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.cards = cards
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

}
