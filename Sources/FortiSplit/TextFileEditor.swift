import SwiftUI

/// Панель правки одного текстового файла: подсказка, моноширинный редактор,
/// кнопки «Перечитать» / «Сохранить» и, если нужно, ещё одно действие рядом
/// (для маршрутов это «Применить сейчас»).
struct TextFileEditor: View {
    struct ExtraAction {
        let title: String
        let help: String
        let enabled: Bool
        let action: () -> Void
    }

    let hint: String
    let saveTitle: String
    @Binding var text: String
    var onReload: () -> Void
    var onSave: () -> Void
    var extra: ExtraAction? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 460, minHeight: 320)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.3)))

            HStack {
                Button("Reload", action: onReload)
                Spacer()
                if let extra {
                    Button(extra.title, action: extra.action)
                        .disabled(!extra.enabled)
                        .help(extra.help)
                }
                Button(saveTitle, action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(12)
    }
}
