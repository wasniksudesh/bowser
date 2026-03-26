//
//  TimezoneConverterWidget.swift
//  Bowser
//
//  Self-contained world clock widget.
//  Shows current time in multiple user-selected timezones.
//

import SwiftUI

// =============================================================================
// MARK: - Common Timezones Catalog
// =============================================================================

private struct TimezoneEntry: Identifiable {
    let id: String       // TimeZone identifier e.g. "America/New_York"
    let cityName: String // Short display label
}

private let commonTimezones: [TimezoneEntry] = [
    TimezoneEntry(id: "UTC",                   cityName: "UTC"),
    TimezoneEntry(id: "America/New_York",       cityName: "New York"),
    TimezoneEntry(id: "America/Chicago",        cityName: "Chicago"),
    TimezoneEntry(id: "America/Denver",         cityName: "Denver"),
    TimezoneEntry(id: "America/Los_Angeles",    cityName: "Los Angeles"),
    TimezoneEntry(id: "America/Sao_Paulo",      cityName: "São Paulo"),
    TimezoneEntry(id: "Europe/London",          cityName: "London"),
    TimezoneEntry(id: "Europe/Paris",           cityName: "Paris"),
    TimezoneEntry(id: "Europe/Berlin",          cityName: "Berlin"),
    TimezoneEntry(id: "Europe/Moscow",          cityName: "Moscow"),
    TimezoneEntry(id: "Asia/Dubai",             cityName: "Dubai"),
    TimezoneEntry(id: "Asia/Kolkata",           cityName: "Mumbai"),
    TimezoneEntry(id: "Asia/Singapore",         cityName: "Singapore"),
    TimezoneEntry(id: "Asia/Shanghai",          cityName: "Shanghai"),
    TimezoneEntry(id: "Asia/Tokyo",             cityName: "Tokyo"),
    TimezoneEntry(id: "Asia/Seoul",             cityName: "Seoul"),
    TimezoneEntry(id: "Australia/Sydney",       cityName: "Sydney"),
    TimezoneEntry(id: "Pacific/Auckland",       cityName: "Auckland"),
]

private func cityName(for identifier: String) -> String {
    commonTimezones.first { $0.id == identifier }?.cityName
        ?? identifier.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ")
        ?? identifier
}

// =============================================================================
// MARK: - Timezone Row
// =============================================================================

private struct TimezoneRow: View {
    let identifier: String
    let now: Date
    let localCalendar: Calendar
    var onRemove: () -> Void

    @State private var isHovering = false

    private var tz: TimeZone { TimeZone(identifier: identifier) ?? .gmt }

    private var timeString: String {
        var cal = Calendar.current
        cal.timeZone = tz
        let fmt = DateFormatter()
        fmt.timeZone = tz
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: now)
    }

    private var abbrev: String {
        tz.abbreviation(for: now) ?? ""
    }

    private var dayOffsetLabel: String? {
        let localDay = localCalendar.startOfDay(for: now)
        var remoteCal = Calendar.current
        remoteCal.timeZone = tz
        let remoteDay = remoteCal.startOfDay(for: now)
        let diff = localCalendar.dateComponents([.day], from: localDay, to: remoteDay).day ?? 0
        if diff == 1 { return "+1 day" }
        if diff == -1 { return "-1 day" }
        if diff > 1 { return "+\(diff) days" }
        if diff < -1 { return "\(diff) days" }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cityName(for: identifier))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(abbrev)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let offset = dayOffsetLabel {
                    Text(offset)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                Text(timeString)
                    .font(.system(size: 17, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .transition(.opacity)
            } else {
                Color.clear.frame(width: 22, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

// =============================================================================
// MARK: - Add Timezone Picker
// =============================================================================

private struct AddTimezoneSheet: View {
    let existing: [String]
    var onAdd: (String) -> Void

    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [TimezoneEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return commonTimezones.filter { entry in
            !existing.contains(entry.id)
                && (q.isEmpty || entry.cityName.lowercased().contains(q) || entry.id.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search cities…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        Button {
                            onAdd(entry.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(entry.cityName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(entry.id.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.primary.opacity(0.0001))

                        if entry.id != filtered.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .frame(width: 240, height: 300)
    }
}

// =============================================================================
// MARK: - Timezone Converter Widget View
// =============================================================================

/// Self-contained world clock widget. Reads/writes timezones from widget configuration.
struct TimezoneConverterWidgetView: View {
    let widgetId: UUID
    @Binding var configuration: [String: String]
    let widgetManager: WidgetManager

    @State private var showAddSheet = false

    private let localCalendar: Calendar = .current

    private var timezoneIdentifiers: [String] {
        let raw = configuration["timezones"] ?? "UTC,America/New_York"
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private func save(_ identifiers: [String]) {
        var updated = configuration
        updated["timezones"] = identifiers.joined(separator: ",")
        widgetManager.updateConfig(widgetId, configuration: updated)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                timezoneList(now: context.date)
                addButton
            }
        }
        .popover(isPresented: $showAddSheet) {
            AddTimezoneSheet(existing: timezoneIdentifiers) { newId in
                var ids = timezoneIdentifiers
                ids.append(newId)
                save(ids)
            }
        }
    }

    // MARK: - Timezone List

    private func timezoneList(now: Date) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(timezoneIdentifiers.enumerated()), id: \.element) { idx, identifier in
                    TimezoneRow(
                        identifier: identifier,
                        now: now,
                        localCalendar: localCalendar,
                        onRemove: {
                            var ids = timezoneIdentifiers
                            ids.remove(at: idx)
                            save(ids)
                        }
                    )
                    if idx < timezoneIdentifiers.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                            .opacity(0.4)
                    }
                }
            }
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("Add timezone")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// =============================================================================
// MARK: - Builtin Widget Content Router
// =============================================================================

/// Dispatches to the correct builtin widget view based on the typeId stored in outputComponentType
struct BuiltinWidgetContentView: View {
    let widget: HomescreenWidgetInstance
    let widgetManager: WidgetManager

    @State private var localConfig: [String: String] = [:]

    var body: some View {
        Group {
            switch widget.outputComponentType {
            case "timezone-converter":
                TimezoneConverterWidgetView(
                    widgetId: widget.id,
                    configuration: configBinding,
                    widgetManager: widgetManager
                )
            default:
                VStack {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Unknown widget: \(widget.outputComponentType)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            localConfig = widget.configuration
        }
    }

    /// Binding that writes through to WidgetManager on change
    private var configBinding: Binding<[String: String]> {
        Binding(
            get: {
                // Always reflect latest from manager
                widgetManager.widgets.first(where: { $0.id == widget.id })?.configuration ?? widget.configuration
            },
            set: { newVal in
                widgetManager.updateConfig(widget.id, configuration: newVal)
            }
        )
    }
}
