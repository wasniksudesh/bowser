//
//  AgentSessionListView.swift
//  Bowser
//
//  Sidebar view for Agent Mode showing session history
//

import SwiftUI

// =============================================================================
// MARK: - Agent Session List View
// =============================================================================

/// Sidebar view for Agent Mode
/// Shows list of past sessions and "New Session" button
struct AgentSessionListView: View {
    
    @Bindable var browserState: BrowserState
    
    private var agentState: AgentState {
        browserState.agentState
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with New Session button
            headerSection
            
            Divider()
            
            // Session list or empty state
            if agentState.sessions.isEmpty {
                emptyStateSection
            } else {
                sessionListSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text("Agent")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // New Session Button
            Button(action: {
                agentState.createNewSession()
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .help("New Agent Session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    // MARK: - Session List Section
    
    private var sessionListSection: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(agentState.sessions) { session in
                    SessionRowView(
                        session: session,
                        isActive: agentState.currentSession?.id == session.id,
                        onTap: {
                            agentState.currentSession = session
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Empty State Section
    
    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No Agent Sessions")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Start a new session to execute tasks with AI agents")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Button(action: {
                agentState.createNewSession()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Session")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// =============================================================================
// MARK: - Session Row View
// =============================================================================

/// Individual session row in the sidebar
private struct SessionRowView: View {
    
    let session: AgentSession
    let isActive: Bool
    let onTap: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Query preview
                Text(session.query)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    // Status indicator
                    statusBadge
                    
                    Spacer()
                    
                    // Timestamp
                    Text(formatTimestamp(session.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isActive ? Color(nsColor: .controlBackgroundColor) :
                        isHovering ? Color.primary.opacity(0.04) :
                        Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isActive ? Color.blue.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(session.status.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusColor: Color {
        switch session.status {
        case .planning:
            return .blue
        case .awaitingContext, .awaitingInput:
            return .orange
        case .awaitingApproval:
            return .orange
        case .executing:
            return .purple
        case .running:
            return .cyan
        case .completed:
            return .green
        case .failed:
            return .red
        case .ready:
            return .green
        case .clarifying:
            return .yellow
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AgentSessionListView_Previews: PreviewProvider {
    static var previews: some View {
        let browserState = BrowserState()
        
        // Add some mock sessions
        let session1 = AgentSession(query: "List last 5 GitHub commits and summarize changes")
        session1.status = .completed
        
        let session2 = AgentSession(query: "Analyze website performance metrics")
        session2.status = .executing
        
        browserState.agentState.sessions = [session1, session2]
        browserState.agentState.currentSession = session1
        
        return AgentSessionListView(browserState: browserState)
            .frame(width: 280, height: 600)
    }
}
#endif
