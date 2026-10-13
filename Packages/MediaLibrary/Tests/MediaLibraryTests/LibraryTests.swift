import Testing

/// Every library suite, one at a time: SwiftData containers (and the
/// version 1 upgrade above all) mustn't be set up on several threads at once.
@Suite("Library", .serialized)
struct LibraryTests {}
