import QuillCodeCore

/// `WorkspaceBoundary` moved to QuillCodeCore so lower layers (e.g. QuillCodeSafety's permission
/// rules) can share the exact same lexical + symlink-resolved path normalization the tool
/// executors enforce. This alias keeps the long-standing `QuillCodeTools.WorkspaceBoundary`
/// spelling working for the tool executors and their tests.
public typealias WorkspaceBoundary = QuillCodeCore.WorkspaceBoundary
