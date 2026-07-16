import Foundation
import QuillCodeCore

struct SSHConfigHostResolver {
    let executable: String
    let configURL: URL

    func resolve(alias: String) -> SSHHostConfiguration? {
        guard SSHConfigParser.isConcreteHostAlias(alias) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "-G", "-F", configURL.path, "--", alias]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let waiter = ProcessCompletionWaiter(process: process)

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = ProcessOutputCollector(stdout: stdout, stderr: stderr)
        output.start()
        guard waiter.wait(for: process, timeoutSeconds: 3) == .finished else {
            output.wait()
            return nil
        }
        output.wait()
        guard process.terminationStatus == 0 else { return nil }
        return Self.configuration(alias: alias, output: String(decoding: output.stdout, as: UTF8.self))
    }

    static func configuration(alias: String, output: String) -> SSHHostConfiguration? {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \Character.isNewline) {
            let components = line.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            guard components.count == 2 else { continue }
            let key = components[0].lowercased()
            guard values[key] == nil else { continue }
            values[key] = String(components[1])
        }
        guard let hostName = values["hostname"], !hostName.isEmpty else { return nil }
        let port = values["port"].flatMap(Int.init).flatMap { (1...65_535).contains($0) ? $0 : nil }
        let user = values["user"].flatMap { $0.isEmpty ? nil : $0 }
        return SSHHostConfiguration(alias: alias, hostName: hostName, user: user, port: port)
    }
}
