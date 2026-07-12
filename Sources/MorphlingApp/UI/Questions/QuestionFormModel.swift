import Foundation
import Observation

@MainActor @Observable final class QuestionFormModel {
    let questions: [AgentQuestion]; private(set) var selections: [String:Set<String>] = [:]; private(set) var freeText: [String:String] = [:]; private(set) var isSubmitting = false
    init(questions: [AgentQuestion]) { self.questions = questions }
    var canSubmit: Bool { !isSubmitting && questions.allSatisfy { q in !(selections[q.id] ?? []).isEmpty || !(freeText[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    func select(choiceID: String, for questionID: String) { guard let q = questions.first(where: {$0.id == questionID}) else { return }; if q.isMultiSelect { var set = selections[questionID] ?? []; if set.contains(choiceID) { set.remove(choiceID) } else { set.insert(choiceID) }; selections[questionID] = set } else { selections[questionID] = [choiceID] } }
    func setText(_ text: String, for id: String) { freeText[id] = text }
}
