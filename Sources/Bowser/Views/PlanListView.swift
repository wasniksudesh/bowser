//
//  PlanListView.swift
//  Bowser
//
//  Main plan list view for multi-plan management
//

import SwiftUI

// =============================================================================
// MARK: - Plan List View
// =============================================================================

/// Main view for displaying and managing multiple plans
/// Shows list of plans with search, create, rename, fork, and delete operations
struct PlanListView: View {
    
    @Bindable var planState: PlanState
    
    @State private var searchText: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var planToDelete: PlanMetadata?
    
    /// Filtered plans based on search text
    private var filteredPlans: [PlanMetadata] {
        if searchText.isEmpty {
            return planState.availablePlans
        }
        
        let lowercasedSearch = searchText.lowercased()
        return planState.availablePlans.filter { plan in
            plan.name.lowercased().contains(lowercasedSearch) ||
            plan.intent.lowercased().contains(lowercasedSearch)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Search field
            searchSection
            
            Divider()
            
            // Plan list or empty state
            if filteredPlans.isEmpty {
                emptyStateSection
            } else {
                planListSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .alert("Delete Plan", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let plan = planToDelete {
                    planState.deletePlan(id: plan.id)
                }
            }
        } message: {
            if let plan = planToDelete {
                Text("Are you sure you want to delete \"\(plan.name)\"? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text("Plans")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Create new plan button
            Button(action: createNewPlan) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Create new plan")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            TextField("Search plans...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Plan List Section
    
    private var planListSection: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredPlans) { plan in
                    PlanRowView(
                        plan: plan,
                        isSelected: planState.currentPlanId == plan.id,
                        onSelect: {
                            selectPlan(plan)
                        },
                        onRename: { newName in
                            renamePlan(plan, newName: newName)
                        },
                        onFork: {
                            forkPlan(plan)
                        },
                        onDelete: {
                            confirmDeletePlan(plan)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Empty State Section
    
    private var emptyStateSection: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Image(systemName: searchText.isEmpty ? "lightbulb" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            // Message
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No plans yet" : "No plans found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(searchText.isEmpty 
                     ? "Create your first plan to get started"
                     : "Try a different search term")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Create button (only for empty state, not search)
            if searchText.isEmpty {
                Button(action: createNewPlan) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Create Plan")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
    
    // MARK: - Actions
    
    private func createNewPlan() {
        planState.createNewPlan()
    }
    
    private func selectPlan(_ plan: PlanMetadata) {
        planState.loadPlan(id: plan.id)
    }
    
    private func renamePlan(_ plan: PlanMetadata, newName: String) {
        // Rename without loading the full plan
        planState.renamePlan(id: plan.id, newName: newName)
        
        // Update current plan name if this is the active plan
        if planState.currentPlanId == plan.id {
            planState.currentPlanName = newName
        }
    }
    
    private func forkPlan(_ plan: PlanMetadata) {
        if let newPlanId = planState.forkPlan(id: plan.id) {
            // Optionally load the forked plan
            // planState.loadPlan(id: newPlanId)
            print("[PlanListView] Forked plan: \(plan.name)")
        }
    }
    
    private func confirmDeletePlan(_ plan: PlanMetadata) {
        planToDelete = plan
        showDeleteConfirmation = true
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct PlanListView_Previews: PreviewProvider {
    static var previews: some View {
        let planState = PlanState()
        
        // Add some sample plans
        planState.availablePlans = [
            PlanMetadata(
                name: "Google Interview Prep",
                intent: "Prepare for Google software engineering interviews",
                nodeCount: 20,
                completedNodeCount: 12
            ),
            PlanMetadata(
                name: "Learn Swift",
                intent: "Master Swift programming language",
                nodeCount: 8,
                completedNodeCount: 5
            ),
            PlanMetadata(
                name: "Japan Trip Planning",
                intent: "Plan a 10-day trip to Japan",
                nodeCount: 15,
                completedNodeCount: 3
            )
        ]
        
        return PlanListView(planState: planState)
            .frame(width: 280, height: 600)
    }
}
#endif
