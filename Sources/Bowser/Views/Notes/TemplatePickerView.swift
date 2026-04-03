// TemplatePickerView.swift - Note template selection sheet
// Presents built-in templates grouped by category.
// Used from both the New Note flow and the recording start flow.

import SwiftUI

// =============================================================================
// MARK: - Template Picker View
// =============================================================================

/// Sheet that lets the user pick a NoteTemplate.
/// `onSelect` is called with the chosen template; `onSkip` dismisses without selection.
struct TemplatePickerView: View {

    var onSelect: (NoteTemplate) -> Void
    var onSkip: () -> Void

    @State private var selectedCategory: NoteTemplateCategory? = nil
    @Environment(\.dismiss) private var dismiss

    private var displayedGroups: [(NoteTemplateCategory, [NoteTemplate])] {
        if let cat = selectedCategory {
            return NoteTemplate.byCategory.filter { $0.0 == cat }
        }
        return NoteTemplate.byCategory
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryFilter
            Divider()
            templateList
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose a Template")
                    .font(.system(size: 17, weight: .semibold))
                Text("Templates pre-fill your note and guide the AI summary.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onSkip()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "All", category: nil)
                ForEach(NoteTemplateCategory.allCases, id: \.self) { cat in
                    categoryChip(label: cat.rawValue, category: cat)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private func categoryChip(label: String, category: NoteTemplateCategory?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedCategory == category
                          ? Color.accentColor.opacity(0.15)
                          : Color.primary.opacity(0.06))
            )
            .foregroundStyle(selectedCategory == category ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Template List

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(displayedGroups, id: \.0) { category, templates in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: category.icon)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 8
                        ) {
                            ForEach(templates) { template in
                                TemplateCard(template: template) {
                                    onSelect(template)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Templates guide AI summaries — your note isn't locked to the structure.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Skip") {
                onSkip()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// =============================================================================
// MARK: - Template Card
// =============================================================================

private struct TemplateCard: View {
    let template: NoteTemplate
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: template.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                    Text(template.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Section pills
                HStack(spacing: 4) {
                    ForEach(template.sections.prefix(3)) { section in
                        Text(section.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    if template.sections.count > 3 {
                        Text("+\(template.sections.count - 3)")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.07) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isHovered ? Color.accentColor.opacity(0.4) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
