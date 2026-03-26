// TabTreeRowView.swift - Hierarchical Tab Display Component
// Apple-style curved connector lines for parent-child relationships

import SwiftUI

// =============================================================================
// MARK: - Apple-Style Curved Connector Shape
// =============================================================================

/// Custom shape that draws an Apple-style curved L-connector
/// Used to connect parent tabs to their children with a smooth curve
struct CurvedConnectorShape: Shape {
    let isLast: Bool  // Is this the last child in the list?
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start from top-center (continuing from parent's vertical line)
        let startX = rect.minX + 8
        let startY = rect.minY
        
        // End at right side, vertically centered
        let endX = rect.maxX
        let endY = rect.midY
        
        // Draw vertical line from top to the curve point
        path.move(to: CGPoint(x: startX, y: startY))
        
        // Curve radius
        let radius: CGFloat = 8
        
        // Draw line down to where curve begins
        let curveStartY = endY - radius
        path.addLine(to: CGPoint(x: startX, y: curveStartY))
        
        // Draw curved corner (quarter circle)
        path.addArc(
            center: CGPoint(x: startX + radius, y: curveStartY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        
        // Draw horizontal line to the tab
        path.addLine(to: CGPoint(x: endX, y: endY))
        
        // If not the last child, continue vertical line below
        if !isLast {
            path.move(to: CGPoint(x: startX, y: endY))
            path.addLine(to: CGPoint(x: startX, y: rect.maxY))
        }
        
        return path
    }
}

/// Shape for continuing vertical line through multiple children
struct VerticalConnectorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 8
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
    }
}

// =============================================================================
// MARK: - Tab Tree Row View
// =============================================================================

/// Individual tab row with Apple-style tree hierarchy visualization
/// Renders curved connector lines based on depth level
struct TabTreeRowView: View {
    
    let tab: Tab
    let depth: Int              // Nesting level (0 = root)
    let hasChildren: Bool
    let isExpanded: Bool
    let isActive: Bool
    let isInSplit: Bool
    let isLastChild: Bool       // NEW: Is this the last child in its parent's list?
    let ancestorIsLast: [Bool]  // NEW: For each depth level, is that ancestor the last child?
    
    let onSelect: () -> Void
    let onClose: () -> Void
    let onPin: () -> Void
    let onToggleExpand: () -> Void
    let onOpenChildTab: () -> Void
    
    @State private var isHovering = false
    
    /// Connector line color - Apple uses a subtle gray
    private var connectorColor: Color {
        Color.secondary.opacity(0.35)
    }
    
    /// Connector stroke width
    private let connectorWidth: CGFloat = 1.5
    
    /// Indent width per nesting level
    private let indentWidth: CGFloat = 24
    
    var body: some View {
        HStack(spacing: 0) {
            // Apple-style tree connector lines
            appleStyleConnectors
            
            // Expand/collapse toggle (only for parent tabs)
            if hasChildren {
                expandCollapseButton
            } else if depth > 0 {
                // Spacer to align with expand button
                Spacer().frame(width: 4)
            }
            
            // Tab content
            tabContent
        }
        .frame(height: 36)
    }
    
    // MARK: - Apple-Style Connectors
    
    private var appleStyleConnectors: some View {
        HStack(spacing: 0) {
            // Draw connectors for each depth level
            ForEach(0..<depth, id: \.self) { level in
                if level < depth - 1 {
                    // Intermediate levels: draw vertical line if ancestor is NOT last
                    if level < ancestorIsLast.count && !ancestorIsLast[level] {
                        VerticalConnectorShape()
                            .stroke(connectorColor, lineWidth: connectorWidth)
                            .frame(width: indentWidth)
                    } else {
                        // Ancestor was last child, no line needed
                        Spacer().frame(width: indentWidth)
                    }
                } else {
                    // Last level: draw curved connector
                    CurvedConnectorShape(isLast: isLastChild)
                        .stroke(connectorColor, style: StrokeStyle(lineWidth: connectorWidth, lineCap: .round, lineJoin: .round))
                        .frame(width: indentWidth)
                }
            }
        }
    }
    
    // MARK: - Expand/Collapse Button
    
    private var expandCollapseButton: some View {
        Button(action: onToggleExpand) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)  // Larger hit area for easier clicking
                .contentShape(Rectangle())     // Ensure entire area is clickable
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tab Content
    
    private var tabContent: some View {
        HStack(spacing: 10) {
            // Favicon
            faviconView
            
            // Tab title
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Loading indicator
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
            
            // Hover actions
            if isHovering && !tab.isLoading {
                HStack(spacing: 4) {
                    // Pin button
                    Button(action: onPin) {
                        Image(systemName: tab.isPinned ? "pin.slash.fill" : "pin")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tab.isPinned ? "Unpin" : "Pin")
                    
                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            print("[DEBUG TabTreeRowView] onTapGesture FIRED for tab: \(tab.id) - \(tab.title)")
            onSelect()
        }
        .contextMenu {
            tabContextMenu
        }
    }
    
    // MARK: - Favicon
    
    @ViewBuilder
    private var faviconView: some View {
        let size: CGFloat = 16

        if tab.tabType == .note {
            Image(systemName: "note.text")
                .font(.system(size: size - 3))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else if let icon = tab.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let faviconData = tab.favicon,
                  let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "globe")
                .font(.system(size: size - 3))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
    
    // MARK: - Styling
    
    private var backgroundFill: Color {
        if isActive {
            return ArcTheme.highlightColor.opacity(0.12)
        } else if isInSplit {
            return ArcTheme.highlightColor.opacity(0.06)
        } else if isHovering {
            return Color.primary.opacity(0.04)
        } else {
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        if isActive {
            return ArcTheme.highlightColor.opacity(0.3)
        } else if isInSplit && !isActive {
            return ArcTheme.highlightColor.opacity(0.15)
        } else {
            return Color.clear
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var tabContextMenu: some View {
        Button("Pin Tab") { onPin() }
        Button("Open as Child Tab") { onOpenChildTab() }
        Divider()
        Button("Copy as Link") {
            NSPasteboard.general.setRichLink(title: tab.title, url: tab.url)
        }
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
        }
        Divider()
        Button("Close Tab", role: .destructive) { onClose() }
    }
}
