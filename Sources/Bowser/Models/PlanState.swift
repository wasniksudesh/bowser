//
//  PlanState.swift
//  Bowser
//
//  State management for Plan Mode
//

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Plan State
// =============================================================================

/// Observable state for Plan Mode
/// Manages the planning workflow: intent → clarification → plan generation
/// Supports multiple plans with file-based persistence
@Observable
@MainActor
final class PlanState {

  /// Storage manager for multi-plan persistence
  private let storageManager = PlanStorageManager.shared

  init() {
    loadAvailablePlans()
  }

  // MARK: - Multi-Plan Management

  /// Currently active plan ID (nil means showing plan list)
  var currentPlanId: UUID?

  /// Current plan name (for display in header)
  var currentPlanName: String = ""

  /// Available plans for list view
  var availablePlans: [PlanMetadata] = []

  /// LLM-suggested name for new plan (from clarification)
  var suggestedPlanName: String?

  // MARK: - Persistence

  struct SavedPlanState: Codable {
    let intent: String
    let hasSubmittedIntent: Bool
    let planRoot: PlanNode?
    let expandedNodeIds: Set<UUID>
  }

  /// Load all available plans from storage
  func loadAvailablePlans() {
    availablePlans = storageManager.loadAllPlans()
  }

  /// Load a specific plan by ID
  func loadPlan(id: UUID) {
    guard let document = storageManager.loadPlan(id: id) else {
      print("[PlanState] Failed to load plan: \(id)")
      return
    }

    // Set current plan
    currentPlanId = id
    currentPlanName = document.metadata.name

    // Load plan state
    intent = document.savedState.intent
    hasSubmittedIntent = document.savedState.hasSubmittedIntent
    planRoot = document.savedState.planRoot
    expandedNodeIds = document.savedState.expandedNodeIds

    // Load clarification data
    clarificationQuestions = document.clarificationQuestions
    clarificationAnswers = document.getClarificationAnswers()

    print("[PlanState] Loaded plan: \(document.metadata.name)")
  }

  /// Save the current plan to storage
  func saveCurrentPlan() {
    guard let planId = currentPlanId else {
      print("[PlanState] No current plan to save")
      return
    }

    let savedState = SavedPlanState(
      intent: intent,
      hasSubmittedIntent: hasSubmittedIntent,
      planRoot: planRoot,
      expandedNodeIds: expandedNodeIds
    )

    // Load existing document to preserve metadata
    guard var document = storageManager.loadPlan(id: planId) else {
      print("[PlanState] Cannot save - plan document not found")
      return
    }

    // Update document with current state
    let updatedDocument = PlanDocument(
      metadata: document.metadata,
      savedState: savedState,
      clarificationQuestions: clarificationQuestions,
      clarificationAnswers: clarificationAnswers
    )

    storageManager.savePlan(updatedDocument)

    // Refresh available plans
    loadAvailablePlans()
  }

  /// Create a new plan with intent
  func createNewPlan() {
    // Clear current state
    currentPlanId = UUID()
    currentPlanName = "New Plan"
    intent = ""
    hasSubmittedIntent = false
    clarificationQuestions = []
    clarificationAnswers = [:]
    planRoot = nil
    expandedNodeIds = []
    selectedLeafNode = nil
    suggestedPlanName = nil

    // Clear other state
    generativeUILayout = nil
    componentDataCache = [:]
    loadingComponentIds = []
    loadingNodeIds = []
    isLoading = false
    errorMessage = nil
  }

  /// Delete a plan by ID
  func deletePlan(id: UUID) {
    storageManager.deletePlan(id: id)

    // If we deleted the current plan, exit to list
    if currentPlanId == id {
      exitToList()
    }

    // Refresh available plans
    loadAvailablePlans()
  }

  /// Fork a plan by ID
  func forkPlan(id: UUID) -> UUID? {
    guard let forkedDocument = storageManager.forkPlan(sourceId: id) else {
      return nil
    }

    // Refresh available plans
    loadAvailablePlans()

    return forkedDocument.metadata.id
  }

  /// Rename the current plan
  func renamePlan(newName: String) {
    guard let planId = currentPlanId else { return }
    renamePlan(id: planId, newName: newName)
    currentPlanName = newName
  }

  /// Rename a plan by ID (can be used without loading the plan)
  func renamePlan(id: UUID, newName: String) {
    guard var document = storageManager.loadPlan(id: id) else { return }

    document.metadata.name = newName
    storageManager.savePlan(document)

    // Refresh available plans
    loadAvailablePlans()
  }

  /// Exit to plan list view
  func exitToList() {
    currentPlanId = nil
    currentPlanName = ""

    // Clear current plan state
    intent = ""
    hasSubmittedIntent = false
    clarificationQuestions = []
    clarificationAnswers = [:]
    planRoot = nil
    expandedNodeIds = []
    selectedLeafNode = nil
    suggestedPlanName = nil

    // Clear other state
    generativeUILayout = nil
    componentDataCache = [:]
    loadingComponentIds = []
    loadingNodeIds = []
    isLoading = false
    errorMessage = nil
  }

  // MARK: - Intent Phase

  /// User's initial intent/goal
  var intent: String = ""

  /// Whether the user has submitted their intent
  var hasSubmittedIntent: Bool = false

  // MARK: - Clarification Phase

  /// Questions asked during clarification
  var clarificationQuestions: [ClarificationQuestion] = []

  /// User's answers to clarification questions (Question ID -> [Option IDs])
  var clarificationAnswers: [UUID: [String]] = [:]

  // MARK: - Plan Phase

  /// The generated plan tree
  var planRoot: PlanNode?

  /// Set of expanded node IDs
  var expandedNodeIds: Set<UUID> = []

  /// Currently selected leaf node (for execution view)
  var selectedLeafNode: PlanNode?

  /// Set of nodes currently loading sub-steps (Lazy Expansion)
  var loadingNodeIds: Set<UUID> = []

  // MARK: - Generative UI State

  /// Layout plan for generative UI
  var generativeUILayout: GenerativeUILayout?

  /// Component data cache (Component ID -> Data)
  var componentDataCache: [String: Any] = [:]

  /// Set of component IDs currently loading
  var loadingComponentIds: Set<String> = []

  // MARK: - UI State

  /// Whether we're currently loading (LLM call in progress)
  var isLoading: Bool = false

  /// Error message to display
  var errorMessage: String?

  // MARK: - API Configuration
  private let baseURL = "http://localhost:8765/api/plan"

  // MARK: - Actions

  /// Submit the user's intent and move to next phase
  func submitIntent() {
    guard !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "Please enter your intent"
      return
    }

    hasSubmittedIntent = true
    errorMessage = nil

    // Generate initial clarification questions
    Task {
      await generateInitialQuestions()
    }
  }

  /// Generate initial clarification questions from LLM
  func generateInitialQuestions() async {
    isLoading = true
    errorMessage = nil

    do {
      // Prepare Request
      let url = URL(string: "\(baseURL)/clarify")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body = ["intent": intent]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      // Execute Request
      let (data, _) = try await URLSession.shared.data(for: request)
      let response = try JSONDecoder().decode(APIClarificationResponse.self, from: data)

      // Store suggested plan name
      self.suggestedPlanName = response.suggested_name

      // Map to Domain Models
      let questions = response.questions.map { apiQ in
        ClarificationQuestion(
          id: UUID(),  // Generate new UUID for internal tracking, could stick to string if refactored
          question: apiQ.text,
          options: apiQ.options.map { apiOpt in
            QuestionOption(
              id: UUID(), text: apiOpt.text, explanation: apiOpt.explanation, originalId: apiOpt.id)
          },
          allowMultipleSelection: apiQ.allowMultiple,
          originalId: apiQ.id
        )
      }

      self.clarificationQuestions = questions
      self.isLoading = false
    } catch {
      print("Error fetching clarification: \(error)")
      self.errorMessage = "Failed to generate questions. Please try again."
      self.isLoading = false
    }
  }

  /// Request next question from LLM (called after each answer)
  func requestNextQuestion() {
    // For now, we only do one round of clarification as per v1 spec simplification or until we implement multi-turn
    // If we wanted dynamic next questions, we'd hit another endpoint.
    // For this iteration, we assume one batch is enough or we proceed to plan.
  }

  /// Generate the plan from intent + clarification answers
  func generatePlan() {
    Task {
      await _generatePlan()
    }
  }

  private func _generatePlan() async {
    isLoading = true

    do {
      // Prepare Request
      let url = URL(string: "\(baseURL)/generate")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      // Map Answers to API format
      let apiAnswers = clarificationQuestions.compactMap { q -> [String: Any]? in
        guard let selectedOptionIds = clarificationAnswers[q.id], !selectedOptionIds.isEmpty else {
          return nil
        }
        // We need to map back to the original string IDs expected by the backend logic if useful,
        // or just send the text/choice. The backend prompt uses the Question ID references.
        // Let's rely on the fact that we chose options.
        // Actually our backend expects 'questionId' and 'selectedOptionIds'.
        // Our Swift View stores UUIDs. We need to find the 'originalId' string.

        return [
          "questionId": q.originalId ?? "unknown",
          "selectedOptionIds": selectedOptionIds.compactMap { selId in
            q.options.first(where: { $0.id.uuidString == selId })?.originalId ?? "unknown"
          },
        ]
      }

      let body: [String: Any] = [
        "intent": intent,
        "clarification_answers": apiAnswers,
      ]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      // Execute Request
      let (data, _) = try await URLSession.shared.data(for: request)
      let response = try JSONDecoder().decode(APIPlanResponse.self, from: data)

      // Map to Domain Model
      let root = convertAPINodeToPlanNode(response.root)

      self.planRoot = root
      self.isLoading = false

      // Create and save plan document
      let planId = UUID()
      let planName = suggestedPlanName ?? "Untitled Plan"

      let metadata = PlanMetadata(
        id: planId,
        name: planName,
        intent: intent,
        createdAt: Date(),
        updatedAt: Date(),
        nodeCount: 0,
        completedNodeCount: 0
      )

      let savedState = SavedPlanState(
        intent: intent,
        hasSubmittedIntent: hasSubmittedIntent,
        planRoot: planRoot,
        expandedNodeIds: expandedNodeIds
      )

      let document = PlanDocument(
        metadata: metadata,
        savedState: savedState,
        clarificationQuestions: clarificationQuestions,
        clarificationAnswers: clarificationAnswers
      )

      storageManager.savePlan(document)

      // Set as current plan
      currentPlanId = planId
      currentPlanName = planName

      // Refresh available plans
      loadAvailablePlans()
    } catch {
      print("Error generating plan: \(error)")
      self.errorMessage = "Failed to create plan. Please try again."
      self.isLoading = false
    }
  }

  /// Generate sub-steps for a specific node (Lazy Expansion)
  func generateSubSteps(for node: PlanNode) {
    guard loadingNodeIds.contains(node.id) == false else { return }

    Task {
      loadingNodeIds.insert(node.id)

      do {
        let url = URL(string: "\(baseURL)/expand")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
          "intent": intent,
          "parent_node_context": node.title + (node.description.map { ": " + $0 } ?? ""),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(APIExpansionResponse.self, from: data)

        let newChildren = response.children.map { convertAPINodeToPlanNode($0) }

        node.children = newChildren
        loadingNodeIds.remove(node.id)
        expandedNodeIds.insert(node.id)
        saveCurrentPlan()
      } catch {
        print("Error expanding node: \(error)")
        loadingNodeIds.remove(node.id)
      }
    }
  }

  /// Send a chat message for a specific node
  func sendChatMessage(node: PlanNode, message: String) {
    let userMsg = ChatMessage(role: "user", content: message)

    // Optimistic update
    node.chatHistory.append(userMsg)
    node.isChatLoading = true

    Task {
      do {
        let url = URL(string: "\(baseURL)/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert history to dictionary for JSON serialization
        let historyDicts = node.chatHistory.map { ["role": $0.role, "content": $0.content] }

        let body: [String: Any] = [
          "intent": intent,
          "node_context": node.title + (node.description.map { "\n" + $0 } ?? ""),
          "history": historyDicts,
          "message": message,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(APIPlanChatResponse.self, from: data)

        let assistantMsg = ChatMessage(role: "assistant", content: response.response)

        node.chatHistory.append(assistantMsg)
        node.isChatLoading = false

        // Handle dynamic updates
        if let newDescription = response.updated_description {
          node.description = newDescription
        }

        if let newLinks = response.updated_links {
          node.links = newLinks.compactMap { dict -> PlanLink? in
            guard let title = dict["title"],
              let urlString = dict["url"],
              let url = URL(string: urlString)
            else { return nil }
            return PlanLink(title: title, url: url)
          }
        }
        self.saveCurrentPlan()
      } catch {
        print("Chat error: \(error)")
        node.chatHistory.append(
          ChatMessage(
            role: "assistant", content: "Sorry, I couldn't get a response. Please try again."))
        node.isChatLoading = false
      }
    }
  }

  // MARK: - Helpers

  private func convertAPINodeToPlanNode(_ apiNode: APIPlanNode) -> PlanNode {
    // Convert raw dictionary links (from API) into PlanLink objects
    let mappedLinks =
      apiNode.links?.compactMap { dict -> PlanLink? in
        guard let title = dict["title"],
          let urlString = dict["url"],
          let url = URL(string: urlString)
        else { return nil }
        return PlanLink(title: title, url: url)
      } ?? []

    return PlanNode(
      title: apiNode.title,
      description: apiNode.description,
      children: apiNode.children?.map { convertAPINodeToPlanNode($0) } ?? [],
      isLeaf: apiNode.isLeaf,
      links: mappedLinks
    )
  }

  // MARK: - Generative UI Methods

  /// Fetch layout plan for the selected leaf node
  func fetchLayoutPlan() async {
    guard let node = selectedLeafNode else { return }

    isLoading = true
    errorMessage = nil

    do {
      let url = URL(string: "http://localhost:8765/api/generative-ui/plan")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.timeoutInterval = 30  // 30 second timeout

      // Build leaf context
      let leafContext: [String: Any] = [
        "title": node.title,
        "description": node.description ?? "",
        "links": node.links.map { ["title": $0.title, "url": $0.url.absoluteString] },
      ]

      // Get available components metadata
      let availableComponents = UIComponentRegistry.components.map { component in
        [
          "type": component.type.rawValue,
          "displayName": component.displayName,
          "description": component.description,
          "compatibleDataTypes": component.compatibleDataTypes,
          "expectedDataSchema": component.expectedDataSchema,
          "sizeHint": component.sizeHint,
        ] as [String: Any]
      }

      let body: [String: Any] = [
        "leafContext": leafContext,
        "availableComponents": availableComponents,
      ]

      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      let (data, _) = try await URLSession.shared.data(for: request)

      // Decode response
      struct LayoutPlanResponse: Codable {
        let layout: GenerativeUILayout
      }

      let response = try JSONDecoder().decode(LayoutPlanResponse.self, from: data)
      self.generativeUILayout = response.layout

      // Start fetching data for all components in parallel
      await fetchAllComponentData()

      isLoading = false
    } catch {
      print("Layout plan fetch error: \(error)")
      errorMessage = "Failed to generate layout"
      isLoading = false
    }
  }

  /// Fetch data for all components in parallel
  private func fetchAllComponentData() async {
    guard let layout = generativeUILayout else { return }

    // Fetch all components in parallel
    await withTaskGroup(of: Void.self) { group in
      for component in layout.components {
        group.addTask {
          await self.fetchComponentData(component: component)
        }
      }
    }
  }

  /// Fetch data for a single component
  private func fetchComponentData(component: UIComponentSpec) async {
    guard let node = selectedLeafNode else { return }

    // Mark as loading
    loadingComponentIds.insert(component.id)

    do {
      let url = URL(string: "http://localhost:8765/api/generative-ui/resolve")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let leafContext: [String: Any] = [
        "title": node.title,
        "description": node.description ?? "",
      ]

      let body: [String: Any] = [
        "componentId": component.id,
        "componentType": component.type,
        "dataPrompt": component.dataPrompt,
        "leafContext": leafContext,
      ]

      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      let (data, _) = try await URLSession.shared.data(for: request)

      // Parse response
      struct ResolveResponse: Codable {
        let componentId: String
        let data: AnyCodable?
        let success: Bool
        let error: String?
      }

      let response = try JSONDecoder().decode(ResolveResponse.self, from: data)

      if response.success, let componentData = response.data?.value {
        componentDataCache[component.id] = componentData
      }

      loadingComponentIds.remove(component.id)
    } catch {
      print("Component data fetch error for \(component.id): \(error)")
      loadingComponentIds.remove(component.id)
    }
  }

  /// Reset the plan state to start over (deprecated - use createNewPlan instead)
  func reset() {
    createNewPlan()
  }
}

// =============================================================================
// MARK: - Clarification Question Model
// =============================================================================

/// Represents a clarification question in the planning flow
struct ClarificationQuestion: Identifiable, Codable {
  let id: UUID
  let question: String
  let options: [QuestionOption]
  let allowMultipleSelection: Bool
  let originalId: String?  // To map back to API

  init(
    id: UUID = UUID(),
    question: String,
    options: [QuestionOption],
    allowMultipleSelection: Bool = false,
    originalId: String? = nil
  ) {
    self.id = id
    self.question = question
    self.options = options
    self.allowMultipleSelection = allowMultipleSelection
    self.originalId = originalId
  }
}

/// Option for a clarification question
struct QuestionOption: Identifiable, Codable {
  let id: UUID
  let text: String
  let explanation: String?
  let originalId: String?

  init(id: UUID = UUID(), text: String, explanation: String? = nil, originalId: String? = nil) {
    self.id = id
    self.text = text
    self.explanation = explanation
    self.originalId = originalId
  }
}

// =============================================================================
// MARK: - Plan Node Model
// =============================================================================

/// Represents a node in the plan tree
@Observable
class PlanNode: Identifiable, Codable {
  let id: UUID
  var title: String
  var description: String?
  var children: [PlanNode]
  var isLeaf: Bool
  var isCompleted: Bool

  // Leaf-specific properties
  var links: [PlanLink]
  var scratchpadContent: String
  var openedTabIds: Set<UUID>

  // Chat state
  var chatHistory: [ChatMessage]
  var isChatLoading: Bool

  init(
    id: UUID = UUID(),
    title: String,
    description: String? = nil,
    children: [PlanNode] = [],
    isLeaf: Bool = false,
    isCompleted: Bool = false,
    links: [PlanLink] = [],
    scratchpadContent: String = "",
    openedTabIds: Set<UUID> = [],
    chatHistory: [ChatMessage] = []
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.children = children
    self.isLeaf = isLeaf
    self.isCompleted = isCompleted
    self.links = links
    self.scratchpadContent = scratchpadContent
    self.openedTabIds = openedTabIds
    self.chatHistory = chatHistory
    self.isChatLoading = false
  }

  // MARK: - Codable

  enum CodingKeys: String, CodingKey {
    case id, title, description, children, isLeaf, isCompleted, links, scratchpadContent,
      openedTabIds, chatHistory
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    children = try container.decode([PlanNode].self, forKey: .children)
    isLeaf = try container.decode(Bool.self, forKey: .isLeaf)
    isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
    links = try container.decode([PlanLink].self, forKey: .links)
    scratchpadContent = try container.decode(String.self, forKey: .scratchpadContent)
    openedTabIds = try container.decode(Set<UUID>.self, forKey: .openedTabIds)
    chatHistory = try container.decode([ChatMessage].self, forKey: .chatHistory)
    isChatLoading = false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(description, forKey: .description)
    try container.encode(children, forKey: .children)
    try container.encode(isLeaf, forKey: .isLeaf)
    try container.encode(isCompleted, forKey: .isCompleted)
    try container.encode(links, forKey: .links)
    try container.encode(scratchpadContent, forKey: .scratchpadContent)
    try container.encode(openedTabIds, forKey: .openedTabIds)
    try container.encode(chatHistory, forKey: .chatHistory)
  }
}

/// Link associated with a plan node
struct PlanLink: Identifiable, Codable {
  let id: UUID
  let title: String
  let url: URL

  init(id: UUID = UUID(), title: String, url: URL) {
    self.id = id
    self.title = title
    self.url = url
  }
}

struct ChatMessage: Identifiable, Codable {
  var id: UUID = UUID()
  let role: String
  let content: String

  enum CodingKeys: String, CodingKey {
    case role, content
  }
}

// =============================================================================
// MARK: - API Decodable Models
// =============================================================================

struct APIClarificationResponse: Codable {
  let suggested_name: String
  let questions: [APIQuestion]
}

struct APIPlanChatResponse: Codable {
  let response: String
  let updated_links: [[String: String]]?  // Optional list of [{"title": "...", "url": "..."}]
  let updated_description: String?
}

struct APIQuestion: Codable {
  let id: String
  let text: String
  let options: [APIOption]
  let allowMultiple: Bool
}

struct APIOption: Codable {
  let id: String
  let text: String
  let explanation: String?
}

struct APIPlanResponse: Codable {
  let root: APIPlanNode
}

struct APIExpansionResponse: Codable {
  let children: [APIPlanNode]
}

struct APIPlanNode: Codable {
  let id: String?
  let title: String
  let description: String?
  let isLeaf: Bool
  let children: [APIPlanNode]?
  let links: [[String: String]]?  // List of dictionaries: [{"title": "...", "url": "..."}]
}

// =============================================================================
// MARK: - Generative UI Models
// =============================================================================

struct ComponentPosition: Codable {
  let row: Int
  let col: Int
}

struct ComponentSize: Codable {
  let width: Double  // 0.0 to 1.0
  let height: String  // "auto", "small", "medium", "large"
}

struct UIComponentSpec: Codable, Identifiable {
  let id: String
  let type: String
  let position: ComponentPosition
  let size: ComponentSize
  let dataPrompt: String
}

struct GenerativeUILayout: Codable {
  let components: [UIComponentSpec]
}
