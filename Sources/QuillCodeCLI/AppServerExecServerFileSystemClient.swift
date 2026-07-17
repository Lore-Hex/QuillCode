import Foundation

extension AppServerExecServerWebSocketClient {
    func readFile(
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) async throws -> Data {
        let result = try await request(method: "fs/readFile", params: .object([
            "path": .string(pathURI),
            "sandbox": sandbox.rpcValue
        ]))
        guard let encoded = result.objectValue?["dataBase64"]?.stringValue,
              let data = Data(base64Encoded: encoded) else {
            throw AppServerExecServerError.invalidResponse(
                "fs/readFile did not return valid base64 data"
            )
        }
        return data
    }

    func writeFile(
        _ data: Data,
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) async throws {
        _ = try await request(method: "fs/writeFile", params: .object([
            "dataBase64": .string(data.base64EncodedString()),
            "path": .string(pathURI),
            "sandbox": sandbox.rpcValue
        ]))
    }

    func createDirectory(
        at pathURI: String,
        recursive: Bool,
        sandbox: AppServerExecServerSandboxContext
    ) async throws {
        _ = try await request(method: "fs/createDirectory", params: .object([
            "path": .string(pathURI),
            "recursive": .bool(recursive),
            "sandbox": sandbox.rpcValue
        ]))
    }

    func metadata(
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) async throws -> AppServerRemoteFileMetadata {
        let result = try await request(method: "fs/getMetadata", params: .object([
            "path": .string(pathURI),
            "sandbox": sandbox.rpcValue
        ]))
        guard let object = result.objectValue,
              let isDirectory = object["isDirectory"]?.boolValue,
              let isFile = object["isFile"]?.boolValue,
              let isSymbolicLink = object["isSymlink"]?.boolValue,
              let rawSize = object["size"]?.numberValue,
              !(isDirectory && isFile) else {
            throw AppServerExecServerError.invalidResponse(
                "fs/getMetadata returned malformed metadata"
            )
        }
        let size = try Self.decodeUInt64(
            rawSize,
            malformedResponse: "fs/getMetadata returned malformed metadata"
        )
        return AppServerRemoteFileMetadata(
            isDirectory: isDirectory,
            isFile: isFile,
            isSymbolicLink: isSymbolicLink,
            size: size
        )
    }

    func canonicalize(
        _ pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) async throws -> String {
        let result = try await request(method: "fs/canonicalize", params: .object([
            "path": .string(pathURI),
            "sandbox": sandbox.rpcValue
        ]))
        guard let path = result.objectValue?["path"]?.stringValue else {
            throw AppServerExecServerError.invalidResponse(
                "fs/canonicalize did not return a path URI"
            )
        }
        return path
    }

    func readDirectory(
        at pathURI: String,
        sandbox: AppServerExecServerSandboxContext
    ) async throws -> [AppServerRemoteDirectoryEntry] {
        let result = try await request(method: "fs/readDirectory", params: .object([
            "path": .string(pathURI),
            "sandbox": sandbox.rpcValue
        ]))
        guard let values = result.objectValue?["entries"]?.arrayValue else {
            throw AppServerExecServerError.invalidResponse(
                "fs/readDirectory did not return an entries array"
            )
        }
        return try values.map { value in
            guard let object = value.objectValue,
                  let name = object["fileName"]?.stringValue,
                  let isDirectory = object["isDirectory"]?.boolValue,
                  let isFile = object["isFile"]?.boolValue,
                  Self.isValidDirectoryEntryName(name),
                  !(isDirectory && isFile) else {
                throw AppServerExecServerError.invalidResponse(
                    "fs/readDirectory returned a malformed entry"
                )
            }
            return AppServerRemoteDirectoryEntry(
                fileName: name,
                isDirectory: isDirectory,
                isFile: isFile
            )
        }
    }

    func remove(
        at pathURI: String,
        recursive: Bool,
        force: Bool,
        sandbox: AppServerExecServerSandboxContext
    ) async throws {
        _ = try await request(method: "fs/remove", params: .object([
            "force": .bool(force),
            "path": .string(pathURI),
            "recursive": .bool(recursive),
            "sandbox": sandbox.rpcValue
        ]))
    }
}
