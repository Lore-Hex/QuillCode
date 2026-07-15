import Foundation
import QuillCodeCLI

@main
struct QuillCodeExecutable {
    static func main() async {
        let status = await QuillCodeCommandRunner().run(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        if status != 0 {
            exit(status)
        }
    }
}
