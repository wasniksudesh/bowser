//
//  ContextArtifactView.swift
//  Bowser
//
//  Editable form for ContextArtifact fields
//  Shows version history and auth section
//

import SwiftUI

// =============================================================================
// MARK: - Context Artifact View
// =============================================================================

/// Editable form for context artifact fields
/// Allows user to fill in required context and authentication
struct ContextArtifactView: View {
    
    @Bindable var context: ContextArtifact
    let onSave: ([String: Any]) -> Void
    
    @State private var hasChanges: Bool = false
    @State private var isOptionalFieldsExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with version indicator
            headerSection
                        
            // Auth section (if needed)
            if !context.auth.isEmpty {
                authSection
            }
            // Context fields - Required fields first
            VStack(alignment: .leading, spacing: 12) {
                // Required fields
                ForEach(Array(context.values.keys.sorted()), id: \.self) { key in
                    if let field = context.values[key], field.required {
                        contextFieldRow(field: field)
                    }
                }
                
                // Optional fields section (collapsible)
                let optionalFields = context.values.values.filter { !$0.required }
                if !optionalFields.isEmpty {
                    optionalFieldsSection(fields: optionalFields)
                }
            }
            
            // Save button
            if hasChanges {
                saveButton
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text("Context")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Version badge
            Text("v\(context.version)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlColor).opacity(0.5))
                )
        }
    }
    
    // MARK: - Context Field Row
    
    private func contextFieldRow(field: ContextValue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                
                if field.required {
                    Text("*")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                }
                
                Spacer()
            }
            
            if !field.description.isEmpty {
                Text(field.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Field input based on type
            fieldInput(for: field)
        }
    }
    
    // MARK: - Optional Fields Section
    
    private func optionalFieldsSection(fields: [ContextValue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button(action: {
                isOptionalFieldsExpanded.toggle()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isOptionalFieldsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Text("Optional Fields")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("(\(fields.count))")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            
            // Optional fields (shown when expanded)
            if isOptionalFieldsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(fields.sorted(by: { $0.name < $1.name })), id: \.name) { field in
                        contextFieldRow(field: field)
                    }
                }
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private func fieldInput(for field: ContextValue) -> some View {
        switch field.fieldType {
        case .string:
            TextField("Enter value...", text: Binding(
                get: { field.value },
                set: { newValue in
                    field.value = newValue
                    hasChanges = true
                }
            ))
            .textFieldStyle(.plain)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            
        case .number:
            TextField("Enter number...", text: Binding(
                get: { field.value },
                set: { newValue in
                    field.value = newValue
                    hasChanges = true
                }
            ))
            .textFieldStyle(.plain)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            
        case .boolean:
            Toggle(isOn: Binding(
                get: { field.value.lowercased() == "true" },
                set: { newValue in
                    field.value = newValue ? "true" : "false"
                    hasChanges = true
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            
        case .secret:
            SecureField("Enter secret...", text: Binding(
                get: { field.value },
                set: { newValue in
                    field.value = newValue
                    hasChanges = true
                }
            ))
            .textFieldStyle(.plain)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
    }
    
    // MARK: - Auth Section
    
    private var authSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.vertical, 4)
            
            Text("Authentication")
                .font(.headline)
                .foregroundStyle(.primary)
            
            ForEach(Array(context.auth.keys.sorted()), id: \.self) { key in
                if let authEntry = context.auth[key] {
                    authEntryRow(key: key, entry: authEntry)
                }
            }
        }
    }
    
    private func authEntryRow(key: String, entry: AuthEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                
                // Required indicator
                Text("*")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.valid ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    
                    Text(entry.valid ? "Valid" : "Invalid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("Strategy: \(entry.strategyUsed)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            SecureField("Enter \(entry.strategyUsed)...", text: Binding(
                get: { entry.value },
                set: { newValue in
                    if var updatedEntry = context.auth[key] {
                        updatedEntry.value = newValue
                        context.auth[key] = updatedEntry
                        hasChanges = true
                    }
                }
            ))
            .textFieldStyle(.plain)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button(action: saveContext) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Context")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func saveContext() {
        var values: [String: Any] = [:]
        
        for (key, field) in context.values {
            values[key] = field.value
        }
        
        onSave(values)
        hasChanges = false
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct ContextArtifactView_Previews: PreviewProvider {
    static var previews: some View {
        let context = ContextArtifact(
            version: 1,
            values: [
                "repo": ContextValue(
                    name: "repo",
                    description: "GitHub repository (owner/name)",
                    value: "",
                    required: true,
                    fieldType: .string
                ),
                "limit": ContextValue(
                    name: "limit",
                    description: "Number of commits to fetch",
                    value: "5",
                    required: false,
                    fieldType: .number
                ),
                "include_diffs": ContextValue(
                    name: "include_diffs",
                    description: "Include commit diffs",
                    value: "true",
                    required: false,
                    fieldType: .boolean
                )
            ],
            auth: [
                "github": AuthEntry(
                    strategyUsed: "token",
                    value: "",
                    valid: false
                )
            ]
        )
        
        return ScrollView {
            ContextArtifactView(context: context) { values in
                print("Saved context: \(values)")
            }
        }
        .frame(width: 600, height: 500)
    }
}
#endif
