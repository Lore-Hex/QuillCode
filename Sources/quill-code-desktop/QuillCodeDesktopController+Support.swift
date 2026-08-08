extension QuillCodeDesktopController {
    func reportIssue() {
        QuillCodeDesktopIssueReporter.open(configuration: updateController.configuration)
    }
}
