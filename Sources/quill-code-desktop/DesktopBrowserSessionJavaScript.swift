import Foundation

enum DesktopBrowserSessionJavaScript {
    static func clickScript(selector: String) throws -> String {
        let selectorLiteral = try javaScriptLiteral(selector)
        return """
        (() => {
          const selector = \(selectorLiteral);
          const element = document.querySelector(selector);
          if (!element) {
            return JSON.stringify({ ok: false, summary: "No element matched selector.", error: `No element matched ${selector}` });
          }
          element.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          element.click();
          const label = element.getAttribute("aria-label") || element.textContent || element.value || element.tagName.toLowerCase();
          return JSON.stringify({ ok: true, summary: `Clicked ${String(label).trim().slice(0, 120) || selector}` });
        })()
        """
    }

    static func typeScript(selector: String, text: String, submit: Bool) throws -> String {
        let selectorLiteral = try javaScriptLiteral(selector)
        let textLiteral = try javaScriptLiteral(text)
        let submitLiteral = submit ? "true" : "false"
        return """
        (() => {
          const selector = \(selectorLiteral);
          const text = \(textLiteral);
          const submit = \(submitLiteral);
          const element = document.querySelector(selector);
          if (!element) {
            return JSON.stringify({ ok: false, summary: "No element matched selector.", error: `No element matched ${selector}` });
          }
          element.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          element.focus();
          if ("value" in element) {
            element.value = text;
          } else if (element.isContentEditable) {
            element.textContent = text;
          } else {
            return JSON.stringify({ ok: false, summary: "Element is not editable.", error: `${selector} is not editable` });
          }
          element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          if (submit) {
            const form = element.form || element.closest("form");
            if (form) {
              form.requestSubmit ? form.requestSubmit() : form.submit();
            } else {
              element.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true }));
              element.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true }));
            }
          }
          return JSON.stringify({ ok: true, summary: `Typed into ${selector}` });
        })()
        """
    }

    private static func javaScriptLiteral(_ value: String) throws -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8)
        else {
            throw DesktopBrowserSessionActionError.encodingFailed
        }
        return literal
    }
}
