// NoteTemplate.swift - Meeting note template model with built-in templates
// Templates pre-fill note bodies and guide the AI summary structure.

import Foundation

// =============================================================================
// MARK: - Template Section
// =============================================================================

/// A named section within a note template, used both as a body scaffold and as
/// structural guidance for the post-meeting AI summary prompt.
struct TemplateSection: Codable, Sendable, Identifiable {
    var id: String { title }
    let title: String
    let description: String   // Shown to the AI when generating summaries
    let placeholder: String   // Pre-filled hint text in the note body
}

// =============================================================================
// MARK: - Note Template
// =============================================================================

struct NoteTemplate: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let category: NoteTemplateCategory
    let description: String
    let icon: String                 // SF Symbol name
    let sections: [TemplateSection]
    let starterMarkdown: String      // Pre-filled body, assembled from sections

    /// Build the starter markdown body from section placeholders.
    static func buildStarter(sections: [TemplateSection]) -> String {
        sections.map { "## \($0.title)\n\($0.placeholder)" }.joined(separator: "\n\n")
    }
}

// =============================================================================
// MARK: - Category
// =============================================================================

enum NoteTemplateCategory: String, Codable, Sendable, CaseIterable {
    case engineering = "Engineering"
    case management  = "Management"
    case general     = "General"

    var icon: String {
        switch self {
        case .engineering: return "wrench.and.screwdriver"
        case .management:  return "person.2"
        case .general:     return "note.text"
        }
    }
}

// =============================================================================
// MARK: - Built-In Templates
// =============================================================================

extension NoteTemplate {

    static let builtIn: [NoteTemplate] = [

        // MARK: Engineering

        NoteTemplate(
            id: "standup",
            title: "Daily Standup",
            category: .engineering,
            description: "Quick daily sync — yesterday, today, blockers.",
            icon: "sunrise",
            sections: [
                TemplateSection(
                    title: "Yesterday",
                    description: "What was accomplished yesterday?",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Today",
                    description: "What is planned for today?",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Blockers",
                    description: "Any obstacles or help needed?",
                    placeholder: "- "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Yesterday", description: "", placeholder: "- "),
                TemplateSection(title: "Today", description: "", placeholder: "- "),
                TemplateSection(title: "Blockers", description: "", placeholder: "- "),
            ])
        ),

        NoteTemplate(
            id: "sprint-retro",
            title: "Sprint Retrospective",
            category: .engineering,
            description: "What went well, what to improve, action items.",
            icon: "arrow.trianglehead.2.clockwise",
            sections: [
                TemplateSection(
                    title: "What Went Well",
                    description: "Successes and positives from the sprint.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "What Could Be Better",
                    description: "Areas for improvement.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Action Items",
                    description: "Concrete follow-up tasks with owners.",
                    placeholder: "- [ ] "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "What Went Well", description: "", placeholder: "- "),
                TemplateSection(title: "What Could Be Better", description: "", placeholder: "- "),
                TemplateSection(title: "Action Items", description: "", placeholder: "- [ ] "),
            ])
        ),

        NoteTemplate(
            id: "tech-design",
            title: "Technical Design Review",
            category: .engineering,
            description: "Architecture, trade-offs, open questions.",
            icon: "cpu",
            sections: [
                TemplateSection(
                    title: "Problem Statement",
                    description: "What problem is being solved?",
                    placeholder: "Describe the problem…"
                ),
                TemplateSection(
                    title: "Proposed Solution",
                    description: "The approach being reviewed.",
                    placeholder: "Describe the solution…"
                ),
                TemplateSection(
                    title: "Trade-offs",
                    description: "Pros, cons, and alternatives considered.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Open Questions",
                    description: "Unresolved decisions or concerns.",
                    placeholder: "- "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Problem Statement", description: "", placeholder: "Describe the problem…"),
                TemplateSection(title: "Proposed Solution", description: "", placeholder: "Describe the solution…"),
                TemplateSection(title: "Trade-offs", description: "", placeholder: "- "),
                TemplateSection(title: "Open Questions", description: "", placeholder: "- "),
            ])
        ),

        NoteTemplate(
            id: "incident-postmortem",
            title: "Incident Postmortem",
            category: .engineering,
            description: "Timeline, root cause, and prevention steps.",
            icon: "exclamationmark.triangle",
            sections: [
                TemplateSection(
                    title: "Incident Summary",
                    description: "Brief overview of the incident — impact, severity, duration.",
                    placeholder: "Describe the incident…"
                ),
                TemplateSection(
                    title: "Timeline",
                    description: "Chronological events during the incident.",
                    placeholder: "- HH:MM — "
                ),
                TemplateSection(
                    title: "Root Cause",
                    description: "The underlying cause(s) identified.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Action Items",
                    description: "Steps to prevent recurrence.",
                    placeholder: "- [ ] "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Incident Summary", description: "", placeholder: "Describe the incident…"),
                TemplateSection(title: "Timeline", description: "", placeholder: "- HH:MM — "),
                TemplateSection(title: "Root Cause", description: "", placeholder: "- "),
                TemplateSection(title: "Action Items", description: "", placeholder: "- [ ] "),
            ])
        ),

        // MARK: Management

        NoteTemplate(
            id: "one-on-one",
            title: "1:1 Meeting",
            category: .management,
            description: "Check-in, topics, feedback, and follow-ups.",
            icon: "person.2.fill",
            sections: [
                TemplateSection(
                    title: "Check-In",
                    description: "How is the person feeling? Any updates?",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Topics",
                    description: "Items to discuss.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Feedback",
                    description: "Feedback exchanged during the meeting.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Follow-Ups",
                    description: "Action items and next steps.",
                    placeholder: "- [ ] "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Check-In", description: "", placeholder: "- "),
                TemplateSection(title: "Topics", description: "", placeholder: "- "),
                TemplateSection(title: "Feedback", description: "", placeholder: "- "),
                TemplateSection(title: "Follow-Ups", description: "", placeholder: "- [ ] "),
            ])
        ),

        NoteTemplate(
            id: "performance-review",
            title: "Performance Review",
            category: .management,
            description: "Achievements, growth areas, and goals.",
            icon: "chart.bar",
            sections: [
                TemplateSection(
                    title: "Achievements",
                    description: "Key accomplishments in the review period.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Growth Areas",
                    description: "Skills or behaviors to develop.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Goals",
                    description: "Goals for the next period.",
                    placeholder: "- "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Achievements", description: "", placeholder: "- "),
                TemplateSection(title: "Growth Areas", description: "", placeholder: "- "),
                TemplateSection(title: "Goals", description: "", placeholder: "- "),
            ])
        ),

        NoteTemplate(
            id: "project-kickoff",
            title: "Project Kickoff",
            category: .management,
            description: "Goals, scope, team, timeline, risks.",
            icon: "flag.checkered",
            sections: [
                TemplateSection(
                    title: "Goals",
                    description: "What success looks like for this project.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Scope",
                    description: "What is and is not included.",
                    placeholder: "In scope: \nOut of scope: "
                ),
                TemplateSection(
                    title: "Team & Roles",
                    description: "Who is responsible for what.",
                    placeholder: "- Name: Role"
                ),
                TemplateSection(
                    title: "Timeline",
                    description: "Key milestones and dates.",
                    placeholder: "- Milestone: Date"
                ),
                TemplateSection(
                    title: "Risks",
                    description: "Known risks and mitigations.",
                    placeholder: "- "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Goals", description: "", placeholder: "- "),
                TemplateSection(title: "Scope", description: "", placeholder: "In scope: \nOut of scope: "),
                TemplateSection(title: "Team & Roles", description: "", placeholder: "- Name: Role"),
                TemplateSection(title: "Timeline", description: "", placeholder: "- Milestone: Date"),
                TemplateSection(title: "Risks", description: "", placeholder: "- "),
            ])
        ),

        // MARK: General

        NoteTemplate(
            id: "brainstorm",
            title: "Brainstorming",
            category: .general,
            description: "Problem, ideas, and next steps.",
            icon: "lightbulb",
            sections: [
                TemplateSection(
                    title: "Problem",
                    description: "The challenge or opportunity being explored.",
                    placeholder: "Describe the problem or opportunity…"
                ),
                TemplateSection(
                    title: "Ideas",
                    description: "All ideas generated — no filtering yet.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Most Promising",
                    description: "Ideas to explore further.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Next Steps",
                    description: "Concrete actions to move forward.",
                    placeholder: "- [ ] "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Problem", description: "", placeholder: "Describe the problem…"),
                TemplateSection(title: "Ideas", description: "", placeholder: "- "),
                TemplateSection(title: "Most Promising", description: "", placeholder: "- "),
                TemplateSection(title: "Next Steps", description: "", placeholder: "- [ ] "),
            ])
        ),

        NoteTemplate(
            id: "lecture",
            title: "Lecture Notes",
            category: .general,
            description: "Key concepts, questions, and summary.",
            icon: "graduationcap",
            sections: [
                TemplateSection(
                    title: "Key Concepts",
                    description: "Main ideas and concepts covered.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Notes",
                    description: "Detailed notes and explanations.",
                    placeholder: ""
                ),
                TemplateSection(
                    title: "Questions",
                    description: "Questions to follow up on.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Summary",
                    description: "Brief recap of the session.",
                    placeholder: ""
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Key Concepts", description: "", placeholder: "- "),
                TemplateSection(title: "Notes", description: "", placeholder: ""),
                TemplateSection(title: "Questions", description: "", placeholder: "- "),
                TemplateSection(title: "Summary", description: "", placeholder: ""),
            ])
        ),

        NoteTemplate(
            id: "open-agenda",
            title: "Open Agenda",
            category: .general,
            description: "Flexible template for any meeting.",
            icon: "list.bullet.rectangle",
            sections: [
                TemplateSection(
                    title: "Agenda",
                    description: "Topics to cover.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Discussion",
                    description: "Notes from the conversation.",
                    placeholder: ""
                ),
                TemplateSection(
                    title: "Decisions",
                    description: "Decisions made during the meeting.",
                    placeholder: "- "
                ),
                TemplateSection(
                    title: "Action Items",
                    description: "Follow-up tasks with owners and due dates.",
                    placeholder: "- [ ] "
                ),
            ],
            starterMarkdown: buildStarter(sections: [
                TemplateSection(title: "Agenda", description: "", placeholder: "- "),
                TemplateSection(title: "Discussion", description: "", placeholder: ""),
                TemplateSection(title: "Decisions", description: "", placeholder: "- "),
                TemplateSection(title: "Action Items", description: "", placeholder: "- [ ] "),
            ])
        ),
    ]

    /// Return templates grouped by category, preserving declaration order.
    static var byCategory: [(NoteTemplateCategory, [NoteTemplate])] {
        NoteTemplateCategory.allCases.compactMap { cat in
            let filtered = builtIn.filter { $0.category == cat }
            return filtered.isEmpty ? nil : (cat, filtered)
        }
    }
}
