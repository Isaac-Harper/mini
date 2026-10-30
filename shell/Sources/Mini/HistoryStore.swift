import Foundation
import SQLite3

struct HistoryEntry: Identifiable, Equatable {
    let url: String
    let title: String
    let lastVisit: Date
    let visitCount: Int

    var id: String { url }

    var displayTitle: String { title.isEmpty ? (URLInput.host(of: url) ?? url) : title }
}

enum Frecency {
    static func score(visitCount: Int, lastVisit: Date, now: Date) -> Double {
        let days = now.timeIntervalSince(lastVisit) / 86_400
        let recencyWeight: Double = switch days {
        case ..<4: 100
        case ..<14: 70
        case ..<31: 50
        case ..<90: 30
        default: 10
        }
        return Double(visitCount) * recencyWeight
    }

    static func ranked(_ entries: [HistoryEntry], now: Date) -> [HistoryEntry] {
        entries.sorted { first, second in
            let firstScore = score(visitCount: first.visitCount, lastVisit: first.lastVisit, now: now)
            let secondScore = score(visitCount: second.visitCount, lastVisit: second.lastVisit, now: now)
            return firstScore == secondScore ? first.lastVisit > second.lastVisit : firstScore > secondScore
        }
    }
}

@MainActor
final class HistoryLibrary {
    private let directory: URL
    private var stores: [String: HistoryStore] = [:]
    var onChange: (() -> Void)?

    init(directory: URL) {
        self.directory = directory
    }

    static func isRecordable(_ url: String) -> Bool {
        url.hasPrefix("https://") || url.hasPrefix("http://")
    }

    func store(forSpace identifier: String) -> HistoryStore {
        if let store = stores[identifier] { return store }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create history directory \(directory.path): \(error)")
        }
        let store = HistoryStore(file: file(forSpace: identifier))
        stores[identifier] = store
        return store
    }

    func recordVisit(url: String, title: String, inSpace identifier: String) {
        guard Self.isRecordable(url) else { return }
        store(forSpace: identifier).recordVisit(url: url, title: title, at: Date())
        onChange?()
    }

    func updateTitle(_ title: String, url: String, inSpace identifier: String) {
        guard Self.isRecordable(url), !title.isEmpty else { return }
        store(forSpace: identifier).updateTitle(title, url: url)
        onChange?()
    }

    func removeHistory(ofSpace identifier: String) {
        stores.removeValue(forKey: identifier)?.close()
        removeFiles(forSpace: identifier)
    }

    func removeHistory(ofSpacesOtherThan liveIdentifiers: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(".sqlite") {
            let identifier = String(name.dropLast(".sqlite".count))
            if !liveIdentifiers.contains(identifier) {
                removeHistory(ofSpace: identifier)
            }
        }
    }

    private func file(forSpace identifier: String) -> URL {
        directory.appendingPathComponent("\(identifier).sqlite")
    }

    private func removeFiles(forSpace identifier: String) {
        let base = file(forSpace: identifier).path
        for path in [base, base + "-wal", base + "-shm"] where FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                NSLog("Mini: could not remove history file %@: %@", (path as NSString).lastPathComponent, String(describing: error))
            }
        }
    }
}

@MainActor
final class HistoryStore {
    private var database: OpaquePointer?
    private(set) var revision = 0

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(file: URL) {
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            fatalError("Could not open history database \(file.lastPathComponent): \(Self.message(database))")
        }
        execute("PRAGMA journal_mode = WAL")
        execute("""
            CREATE TABLE IF NOT EXISTS visits (
                url TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                last_visit REAL NOT NULL,
                visit_count INTEGER NOT NULL
            )
            """)
        execute("CREATE INDEX IF NOT EXISTS visits_by_last_visit ON visits (last_visit DESC)")
    }

    func close() {
        sqlite3_close_v2(database)
        database = nil
    }

    func recordVisit(url: String, title: String, at date: Date) {
        run("""
            INSERT INTO visits (url, title, last_visit, visit_count) VALUES (?1, ?2, ?3, 1)
            ON CONFLICT(url) DO UPDATE SET
                visit_count = visit_count + 1,
                last_visit = excluded.last_visit,
                title = CASE WHEN excluded.title = '' THEN title ELSE excluded.title END
            """, [.text(url), .text(title), .real(date.timeIntervalSince1970)])
        revision += 1
    }

    func updateTitle(_ title: String, url: String) {
        run("UPDATE visits SET title = ?1 WHERE url = ?2", [.text(title), .text(url)])
        revision += 1
    }

    func recent(limit: Int) -> [HistoryEntry] {
        entries("SELECT url, title, last_visit, visit_count FROM visits ORDER BY last_visit DESC LIMIT ?1", [.integer(limit)])
    }

    func search(_ query: String, limit: Int) -> [HistoryEntry] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return recent(limit: limit) }
        let conditions = tokens.indices.map { "lower(url || ' ' || title) LIKE ?\($0 + 1) ESCAPE '\\'" }.joined(separator: " AND ")
        let patterns = tokens.map { token in
            Binding.text("%" + token.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%")
        }
        return entries("SELECT url, title, last_visit, visit_count FROM visits WHERE \(conditions) ORDER BY last_visit DESC LIMIT ?\(tokens.count + 1)", patterns + [.integer(limit)])
    }

    func delete(url: String) {
        run("DELETE FROM visits WHERE url = ?1", [.text(url)])
        revision += 1
    }

    func deleteAll() {
        execute("DELETE FROM visits")
        revision += 1
    }

    private enum Binding {
        case text(String)
        case real(Double)
        case integer(Int)
    }

    private func execute(_ sql: String) {
        if sqlite3_exec(database, sql, nil, nil, nil) != SQLITE_OK {
            logFailure()
        }
    }

    private func prepare(_ sql: String, _ bindings: [Binding]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            logFailure()
            return nil
        }
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .real(let value): sqlite3_bind_double(statement, index, value)
            case .integer(let value): sqlite3_bind_int64(statement, index, Int64(value))
            }
        }
        return statement
    }

    private func run(_ sql: String, _ bindings: [Binding]) {
        guard let statement = prepare(sql, bindings) else { return }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_DONE {
            logFailure()
        }
    }

    private func entries(_ sql: String, _ bindings: [Binding]) -> [HistoryEntry] {
        guard let statement = prepare(sql, bindings) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [HistoryEntry] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                logFailure()
                break
            }
            rows.append(HistoryEntry(
                url: String(cString: sqlite3_column_text(statement, 0)),
                title: String(cString: sqlite3_column_text(statement, 1)),
                lastVisit: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                visitCount: Int(sqlite3_column_int64(statement, 3))
            ))
        }
        return rows
    }

    private func logFailure() {
        NSLog("Mini: history database error: %@", Self.message(database))
    }

    private static func message(_ database: OpaquePointer?) -> String {
        database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "no database"
    }
}
