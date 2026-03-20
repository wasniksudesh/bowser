// SearchSettingsView.swift
import SwiftUI

struct SearchSettingsView: View {
  @Bindable var manager: SettingsManager

  var body: some View {
    Section("Search Engine") {
      Picker("Default search engine", selection: $manager.searchEngine) {
        ForEach(SearchEngine.allCases) { engine in
          Text(engine.rawValue).tag(engine)
        }
      }

      if manager.searchEngine == .custom {
        TextField("Search URL (use %s for query)", text: $manager.customSearchUrl)
      }
    }

    Section("Command Bar") {
      Toggle("Show search suggestions", isOn: $manager.showSearchSuggestions)
        .font(.system(size: 13))

      HStack {
        Text("Max history items")
          .font(.system(size: 13))
        Spacer()
        Stepper("\(manager.historyMaxItems)", value: $manager.historyMaxItems, in: 5...50)
          .labelsHidden()
      }
    }
  }
}
