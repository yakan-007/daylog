import SwiftUI

struct SettingsView: View {
    @AppStorage("isDateStampEnabled") private var isDateStampEnabled: Bool = true
    @AppStorage("dateStampFormat") private var dateStampFormat: String = "yy.MM.dd"

    private let formats = ["yy.MM.dd", "yyyy.MM.dd", "MM.dd"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("日付スタンプ")) {
                    Toggle("スタンプを表示", isOn: $isDateStampEnabled)
                    Picker("書式", selection: $dateStampFormat) {
                        ForEach(formats, id: \.self) { fmt in
                            Text(fmt).tag(fmt)
                        }
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}
