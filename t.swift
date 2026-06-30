import Foundation
// Replicate FileToolExecutor.write atomic write onto a symlink target inside workspace
let proj = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("proj")
// Case 1: symlink -> existing OUTSIDE file. guard fileExists == true so /init skips. Show what WOULD happen if write ran anyway (e.g. dangling case path).
let agents = proj.appendingPathComponent("AGENTS.md")
print("fileExists(AGENTS.md path):", FileManager.default.fileExists(atPath: agents.path))
// Now simulate atomic write as FileToolExecutor.write does
do {
  try "SCAFFOLD GENERATED".write(to: agents.standardizedFileURL, atomically: true, encoding: .utf8)
  print("write OK")
} catch { print("write err", error) }
