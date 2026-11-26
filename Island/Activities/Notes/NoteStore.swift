import Foundation

/// One quick note.
struct QuickNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
    var isPinned = false
}

/// The notes you've written, saved on this Mac (in the app's own
/// preferences — never sent anywhere). One note at a time can be pinned
/// to the notch.
@MainActor
final class NoteStore: ObservableObject {

    static let shared = NoteStore()

    private static let defaultsKey = "quickNotes"
    private static let maxNotes = 100

    @Published private(set) var notes: [QuickNote] = []

    var pinned: QuickNote? {
        notes.first { $0.isPinned }
    }

    /// The note the board is showing right now. `nil` is a blank board:
    /// the first keystroke creates the note.
    @Published var editingID: QuickNote.ID?

    var editing: QuickNote? {
        notes.first { $0.id == editingID }
    }

    /// The board's text. Typing saves as you go — there is no Save button.
    var draft: String {
        get { editing?.text ?? "" }
        set { setDraft(newValue) }
    }

    private func setDraft(_ text: String) {

        if let index = notes.firstIndex(where: { $0.id == editingID }) {

            guard notes[index].text != text else { return }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Emptied out: the note goes, the board stays blank.
                notes.remove(at: index)
                editingID = nil
            } else {
                notes[index].text = text
                notes[index].date = Date()
            }

            save()

        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

            let note = QuickNote(text: text)
            notes.insert(note, at: 0)
            editingID = note.id

            if notes.count > Self.maxNotes {
                notes.removeLast(notes.count - Self.maxNotes)
            }

            save()
        }
    }

    /// Opens the board on the pinned note, or blank.
    func openBoard() {
        editingID = pinned?.id
    }

    func startNewNote() {
        editingID = nil
    }

    func pinEditing() {
        guard let id = editingID else { return }
        togglePin(id)
    }

    private init() {

        if
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let saved = try? JSONDecoder().decode([QuickNote].self, from: data)
        {
            notes = saved
        }
    }

    // MARK: - Editing

    @discardableResult
    func add(_ text: String, pin: Bool) -> QuickNote? {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        if pin { unpinAll() }

        let note = QuickNote(text: trimmed, isPinned: pin)

        notes.insert(note, at: 0)

        if notes.count > Self.maxNotes {
            notes.removeLast(notes.count - Self.maxNotes)
        }

        save()

        return note
    }

    func togglePin(_ id: QuickNote.ID) {

        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        let willPin = !notes[index].isPinned

        unpinAll()

        notes[index].isPinned = willPin

        save()
    }

    func unpin() {
        unpinAll()
        save()
    }

    func delete(_ id: QuickNote.ID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// Wipes every saved note, the pinned one included.
    func clearAll() {
        notes.removeAll()
        save()
    }

    private func unpinAll() {
        for index in notes.indices { notes[index].isPinned = false }
    }

    private func save() {

        guard let data = try? JSONEncoder().encode(notes) else { return }

        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
