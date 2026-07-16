import QuillCodePersistence

extension AppServerSession {
    func resetMemory() throws -> CLIJSONValue {
        do {
            try MemoryDirectoryResetter.clear(paths.memoriesDirectory)
            return .object([:])
        } catch {
            throw AppServerRPCError.internalError(
                "failed to reset global memory: \(error.localizedDescription)"
            )
        }
    }
}
