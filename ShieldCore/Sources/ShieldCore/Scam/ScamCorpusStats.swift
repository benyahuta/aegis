// The scam-corpus results baked into this build (SPEC §10.3 Feed & release health: "Scam-corpus
// pass rate baked in at build time"). `ScamCorpusStatsTests` recomputes them from
// Tests/Fixtures and fails when the rules or the corpus change without updating these numbers.
// Shown only on Ben's screen, as counts (never a percentage on a family screen, §10).

import Foundation

public enum ScamCorpusStats {
    /// Clear scams graded `danger`.
    public static let clearScamsDanger = 201
    /// Clear scams in the corpus.
    public static let clearScamsTotal = 208
    /// Benign messages NOT graded `danger`.
    public static let benignNotDanger = 148
    /// Benign messages in the corpus.
    public static let benignTotal = 148
}
