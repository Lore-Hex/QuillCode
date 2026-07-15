import Foundation

enum AppServerDiscoveryParams {
    static func requireEmpty(_ raw: CLIJSONValue, method: String) throws {
        let params = try AppServerParams(raw)
        guard params.object.isEmpty else {
            throw AppServerRPCError.invalidParams("\(method) does not accept parameters")
        }
    }
}
