import Foundation
import GRDB

struct IndexedCard: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "card"

    var id: String
    var noteID: String
    var cardOrder: Int
    var title: String
    var body: String
    var documentClass: String
    var preamble: String
    var engine: String
    var completeSource: String
    var pdfRelativePath: String?
    var sourceHash: String
    var createdAt: Date
    var lastTypesetAt: Date?
    var updatedAt: Date
}

actor AppDatabase {
    static let shared: AppDatabase = {
        do {
            let manager = FileManager.default
            let support = try manager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appending(path: "TeXNote", directoryHint: .isDirectory)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            return try AppDatabase(path: directory.appending(path: "index.sqlite").path)
        } catch {
            fatalError("GRDBの初期化に失敗しました: \(error)")
        }
    }()

    private let writer: DatabasePool

    init(path: String) throws {
        writer = try DatabasePool(path: path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "note") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("folderPath", .text)
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "card") { table in
                table.column("id", .text).primaryKey()
                table.column("noteID", .text).notNull().indexed()
                table.column("cardOrder", .integer).notNull()
                table.column("title", .text).notNull()
                table.column("body", .text).notNull()
                table.column("documentClass", .text).notNull()
                table.column("preamble", .text).notNull()
                table.column("engine", .text).notNull()
                table.column("completeSource", .text).notNull()
                table.column("pdfRelativePath", .text)
                table.column("sourceHash", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(virtualTable: "cardFTS", using: FTS5()) { table in
                table.column("cardID").notIndexed()
                table.column("noteID").notIndexed()
                table.column("title")
                table.column("completeSource")
                table.tokenizer = .unicode61()
            }
        }
        migrator.registerMigration("v2-last-workspace") { db in
            try db.create(table: "lastWorkspace") { table in
                table.column("id", .integer).primaryKey()
                table.column("noteName", .text).notNull()
                table.column("folderPath", .text)
                table.column("documentJSON", .blob).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "lastWorkspacePDF") { table in
                table.column("cardID", .text).primaryKey()
                table.column("pdfData", .blob).notNull()
            }
        }
        migrator.registerMigration("v3-last-selected-card") { db in
            try db.alter(table: "lastWorkspace") { table in
                table.add(column: "selectedCardID", .text)
            }
        }
        migrator.registerMigration("v4-package-save-state") { db in
            try db.alter(table: "lastWorkspace") { table in
                table.add(
                    column: "hasUnsavedPackageChanges",
                    .boolean
                ).notNull().defaults(to: true)
            }
        }
        migrator.registerMigration("v5-package-is-source-of-truth") { db in
            try db.drop(table: "lastWorkspacePDF")
            try db.drop(table: "lastWorkspace")
        }
        migrator.registerMigration("v6-card-dates") { db in
            try db.alter(table: "card") { table in
                table.add(column: "createdAt", .datetime)
                table.add(column: "lastTypesetAt", .datetime)
            }
        }
        try migrator.migrate(writer)
        try writer.write { db in
            try db.execute(sql: "DELETE FROM cardFTS")
            try db.execute(sql: "DELETE FROM card")
            try db.execute(sql: "DELETE FROM note")
        }
    }

    func index(
        document: NoteDocument,
        noteName: String,
        folderURL: URL?
    ) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM cardFTS")
            try db.execute(sql: "DELETE FROM card")
            try db.execute(sql: "DELETE FROM note")
            try db.execute(
                sql: """
                INSERT INTO note(id, name, folderPath, updatedAt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    folderPath = excluded.folderPath,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    document.id.uuidString,
                    noteName,
                    folderURL?.path,
                    document.updatedAt
                ]
            )
            for (order, card) in document.cards.enumerated() {
                let record = IndexedCard(
                    id: card.id.uuidString,
                    noteID: document.id.uuidString,
                    cardOrder: order,
                    title: card.title,
                    body: card.body,
                    documentClass: card.documentClassLine,
                    preamble: card.preamble,
                    engine: card.engine.rawValue,
                    completeSource: card.completeSource,
                    pdfRelativePath: card.pdfRelativePath,
                    sourceHash: card.sourceHash,
                    createdAt: card.createdAt,
                    lastTypesetAt: card.lastTypesetAt,
                    updatedAt: card.updatedAt
                )
                try record.insert(db)
                try db.execute(
                    sql: """
                    INSERT INTO cardFTS(cardID, noteID, title, completeSource)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [
                        record.id,
                        record.noteID,
                        record.title,
                        record.completeSource
                    ]
                )
            }

        }
    }

}
