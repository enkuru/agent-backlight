/// What Claude is doing. When sessions disagree, the highest one wins: question, then thinking, then normal.
public enum AgentState: Int, Comparable, CaseIterable, Sendable {
    case normal
    case thinking
    case question

    public static func < (lhs: AgentState, rhs: AgentState) -> Bool { lhs.rawValue < rhs.rawValue }
}
