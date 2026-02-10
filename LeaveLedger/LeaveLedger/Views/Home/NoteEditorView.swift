import SwiftUI

struct NoteEditorView: View {
    let store: DataStore
    let date: Date
    let editingNote: DateNote?
    let userId: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var noteText: String
    @State private var selectedColor: Color

    // Available colors for notes
    private let availableColors: [Color] = [
        .blue, .green, .purple, .orange, .red, .pink, .teal, .indigo, .cyan, .mint, .yellow
    ]

    init(store: DataStore, date: Date, userId: UUID, editingNote: DateNote? = nil) {
        self.store = store
        self.date = date
        self.userId = userId
        self.editingNote = editingNote

        if let note = editingNote {
            _title = State(initialValue: note.title)
            _noteText = State(initialValue: note.noteText)
            _selectedColor = State(initialValue: note.color)
        } else {
            _title = State(initialValue: "")
            _noteText = State(initialValue: "")
            _selectedColor = State(initialValue: .blue)
        }
    }

    private var isEditing: Bool { editingNote != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Add a custom note to \(DateUtils.shortDate(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Title") {
                    TextField("Short title for calendar pill", text: $title)
                        .autocorrectionDisabled()
                }

                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(availableColors, id: \.self) { color in
                                ColorButton(
                                    color: color,
                                    isSelected: color == selectedColor,
                                    action: {
                                        selectedColor = color
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section("Note") {
                    TextField("Enter your note here...", text: $noteText, axis: .vertical)
                        .lineLimit(5...15)
                        .autocorrectionDisabled()
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let note = editingNote {
                                store.deleteNote(note)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Note")
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveNote()
                        dismiss()
                    }
                    .bold()
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func saveNote() {
        let colorHex = selectedColor.toHex()

        if let existing = editingNote {
            store.updateNote(existing) { note in
                note.title = title
                note.noteText = noteText
                note.colorHex = colorHex
            }
        } else {
            let note = DateNote(
                userId: userId,
                date: date,
                title: title,
                noteText: noteText,
                colorHex: colorHex
            )
            store.addNote(note)
        }
    }
}

struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)

                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .font(.system(size: 20, weight: .bold))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NoteEditorView(
        store: DataStore(inMemory: true),
        date: Date(),
        userId: UUID()
    )
}
