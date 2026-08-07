#!/usr/bin/env python3
"""Validate or run bounded TAU3 banking and BFCL compatibility fixtures."""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
EXACT_MODEL = "deepseek/deepseek-v4-flash-0731"
BASE_URL = "https://api.trustedrouter.com/v1"
CATALOGS = {
    "tau3-banking": ROOT / "docs" / "tau3-banking-eval-catalog.json",
    "bfcl": ROOT / "docs" / "bfcl-eval-catalog.json",
}
DEFAULT_KEY_FILES = (
    Path.home() / ".quillcode" / "secrets" / "trustedrouter_api_key",
    Path.home() / ".quill.code.keyfile",
)
JSON_TYPES = {
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "object": dict,
    "array": list,
}


class EvalError(RuntimeError):
    pass


class InvocationBudget:
    def __init__(self, limit: int):
        self.limit = limit
        self.used = 0

    def charge(self) -> None:
        if self.used >= self.limit:
            raise EvalError(f"paid invocation fuse reached ({self.limit})")
        self.used += 1


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", action="append", choices=sorted(CATALOGS), default=[])
    parser.add_argument("--case", action="append", dest="case_ids", default=[])
    parser.add_argument("--model", default=EXACT_MODEL)
    parser.add_argument("--key-file", type=Path)
    parser.add_argument("--artifact-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=90)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--validate-only", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvalError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise EvalError(f"{path} must contain a JSON object")
    return value


def validate_tool(tool: Any, location: str) -> None:
    if not isinstance(tool, dict):
        raise EvalError(f"{location} must be an object")
    if not isinstance(tool.get("name"), str) or not tool["name"]:
        raise EvalError(f"{location} needs a nonempty name")
    if not isinstance(tool.get("description"), str) or not tool["description"]:
        raise EvalError(f"{location} needs a nonempty description")
    parameters = tool.get("parameters")
    if not isinstance(parameters, dict) or parameters.get("type") != "object":
        raise EvalError(f"{location} parameters must be an object schema")
    properties = parameters.get("properties")
    required = parameters.get("required", [])
    if not isinstance(properties, dict) or not isinstance(required, list):
        raise EvalError(f"{location} has an invalid parameters schema")
    if any(name not in properties for name in required):
        raise EvalError(f"{location} requires an undefined property")


def validate_expected_call(call: Any, tool_names: set[str], location: str) -> None:
    if not isinstance(call, dict) or call.get("name") not in tool_names:
        raise EvalError(f"{location} names an unavailable tool")
    if not isinstance(call.get("arguments", {}), dict):
        raise EvalError(f"{location} arguments must be an object")


def validate_catalog(catalog: dict[str, Any], expected_suite: str) -> list[dict[str, Any]]:
    if catalog.get("version") != 1:
        raise EvalError(f"{expected_suite}: catalog version must be 1")
    if catalog.get("suite") != expected_suite:
        raise EvalError(f"{expected_suite}: suite name mismatch")
    if catalog.get("taskModel") != EXACT_MODEL:
        raise EvalError(f"{expected_suite}: taskModel must be {EXACT_MODEL}")
    max_calls = catalog.get("maxPaidInvocations")
    max_steps = catalog.get("maxStepsPerCase")
    if not isinstance(max_calls, int) or not 1 <= max_calls <= 24:
        raise EvalError(f"{expected_suite}: maxPaidInvocations must be between 1 and 24")
    if not isinstance(max_steps, int) or not 1 <= max_steps <= 4:
        raise EvalError(f"{expected_suite}: maxStepsPerCase must be between 1 and 4")
    upstream = catalog.get("upstream")
    if not isinstance(upstream, dict) or not str(upstream.get("repository", "")).startswith("https://github.com/"):
        raise EvalError(f"{expected_suite}: upstream repository must be explicit")

    common_tools = catalog.get("tools", [])
    if expected_suite == "tau3-banking" and not isinstance(catalog.get("fixtureState"), dict):
        raise EvalError("tau3-banking: fixtureState must be an object")
    if not isinstance(common_tools, list):
        raise EvalError(f"{expected_suite}: tools must be an array")
    for index, tool in enumerate(common_tools):
        validate_tool(tool, f"{expected_suite}.tools[{index}]")

    cases = catalog.get("cases")
    if not isinstance(cases, list) or not cases:
        raise EvalError(f"{expected_suite}: cases must be a nonempty array")
    case_ids: set[str] = set()
    for index, case in enumerate(cases):
        location = f"{expected_suite}.cases[{index}]"
        if not isinstance(case, dict):
            raise EvalError(f"{location} must be an object")
        case_id = case.get("id")
        if not isinstance(case_id, str) or not case_id or case_id in case_ids:
            raise EvalError(f"{location} needs a unique nonempty id")
        case_ids.add(case_id)
        if not isinstance(case.get("category"), str) or not case["category"]:
            raise EvalError(f"{case_id}: category is required")
        if not isinstance(case.get("prompt"), str) or not case["prompt"].strip():
            raise EvalError(f"{case_id}: prompt is required")
        steps = case.get("maxSteps", max_steps)
        if not isinstance(steps, int) or not 1 <= steps <= max_steps:
            raise EvalError(f"{case_id}: maxSteps exceeds the suite limit")

        tools = common_tools if expected_suite == "tau3-banking" else case.get("tools")
        if not isinstance(tools, list) or not tools:
            raise EvalError(f"{case_id}: tools must be a nonempty array")
        for tool_index, tool in enumerate(tools):
            validate_tool(tool, f"{case_id}.tools[{tool_index}]")
        tool_names = {tool["name"] for tool in tools}
        if len(tool_names) != len(tools):
            raise EvalError(f"{case_id}: tool names must be unique")

        expected = case.get("expected")
        if not isinstance(expected, dict):
            raise EvalError(f"{case_id}: expected grader contract is required")
        expected_calls = expected.get("calls", [])
        if not isinstance(expected_calls, list):
            raise EvalError(f"{case_id}: expected calls must be an array")
        for call_index, call in enumerate(expected_calls):
            validate_expected_call(call, tool_names, f"{case_id}.expected.calls[{call_index}]")
        forbidden = expected.get("forbiddenTools", [])
        if not isinstance(forbidden, list) or any(name not in tool_names for name in forbidden):
            raise EvalError(f"{case_id}: forbiddenTools must name available tools")
        if expected_suite == "bfcl" and not expected_calls and not expected.get("requiresFinal"):
            raise EvalError(f"{case_id}: BFCL relevance cases must require a final answer")

    maximum_case_calls = sum(case.get("maxSteps", max_steps) for case in cases)
    if maximum_case_calls > max_calls:
        raise EvalError(
            f"{expected_suite}: case step ceilings total {maximum_case_calls}, above fuse {max_calls}"
        )
    return cases


def selected_catalogs(requested_suites: list[str]) -> list[tuple[str, dict[str, Any]]]:
    suite_names = requested_suites or list(CATALOGS)
    return [(suite, read_json(CATALOGS[suite])) for suite in suite_names]


def select_cases(
    catalogs: list[tuple[str, dict[str, Any]]], requested_ids: list[str]
) -> list[tuple[str, dict[str, Any], dict[str, Any]]]:
    selected = []
    all_ids = set()
    requested = set(requested_ids)
    for suite, catalog in catalogs:
        for case in catalog["cases"]:
            all_ids.add(case["id"])
            if not requested or case["id"] in requested:
                selected.append((suite, catalog, case))
    unknown = sorted(requested - all_ids)
    if unknown:
        raise EvalError(f"unknown case id(s): {', '.join(unknown)}")
    if not selected:
        raise EvalError("no cases selected")
    return selected


def load_api_key(explicit_path: Path | None) -> str:
    value = os.environ.get("QUILLCODE_API_KEY") or os.environ.get("TRUSTEDROUTER_API_KEY")
    if value and value.strip():
        return value.strip()
    paths = (explicit_path,) if explicit_path else DEFAULT_KEY_FILES
    for path in paths:
        if path and path.is_file():
            value = path.read_text(encoding="utf-8").strip()
            if value:
                return value
    raise EvalError(
        "no TrustedRouter key found in QUILLCODE_API_KEY, TRUSTEDROUTER_API_KEY, "
        "or the supported key files"
    )


def prepare_artifact_dir(raw_path: Path | None) -> Path:
    if raw_path:
        path = raw_path if raw_path.is_absolute() else ROOT / raw_path
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = ROOT / ".build" / "quillcode-validation" / "benchmark-compat" / stamp
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise EvalError(f"artifact directory must be absent or empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def tool_prompt(tools: list[dict[str, Any]]) -> str:
    return "\n".join(
        f"- {tool['name']}: {tool['description']}. Parameters JSON schema: "
        f"{json.dumps(tool['parameters'], sort_keys=True, separators=(',', ':'))}"
        for tool in tools
    )


def system_prompt(suite: str, catalog: dict[str, Any], tools: list[dict[str, Any]]) -> str:
    shared = f"""You are QuillCode running a deterministic {suite} compatibility fixture.
Return exactly one JSON object and no markdown.
To answer without a tool: {{"type":"say","text":"..."}}
To call a tool: {{"type":"tool","name":"tool_name","arguments":{{...}}}}
Use only exact tool names and argument keys listed below. Call at most one tool per response.
After a tool result, continue with another required tool or return a concise final answer.
Never fabricate tool results.
"""
    if suite == "tau3-banking":
        shared += catalog["policy"].strip() + "\n"
    else:
        shared += (
            "Select functions and arguments literally from the user request. Do not call a function "
            "for an irrelevant request. When multiple calls are required, emit them one at a time.\n"
        )
    return shared + "Available tools:\n" + tool_prompt(tools)


def decode_json_object(text: str) -> dict[str, Any]:
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        stripped = "\n".join(lines[1:-1]).strip() if len(lines) >= 3 else stripped
    decoder = json.JSONDecoder()
    for index, character in enumerate(stripped):
        if character != "{":
            continue
        try:
            value, _ = decoder.raw_decode(stripped[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    raise EvalError("model did not return a JSON object")


def normalized_action(message: dict[str, Any]) -> dict[str, Any]:
    tool_calls = message.get("tool_calls")
    if isinstance(tool_calls, list) and tool_calls:
        first = tool_calls[0]
        function = first.get("function", {}) if isinstance(first, dict) else {}
        arguments = function.get("arguments", {})
        if isinstance(arguments, str):
            arguments = json.loads(arguments)
        return {"type": "tool", "name": function.get("name"), "arguments": arguments}

    content = message.get("content")
    if isinstance(content, list):
        content = "".join(
            item.get("text", "") for item in content if isinstance(item, dict)
        )
    if not isinstance(content, str):
        raise EvalError("model response has no text content")
    action = decode_json_object(content)
    if isinstance(action.get("function"), dict):
        function = action["function"]
        action = {
            "type": "tool",
            "name": function.get("name"),
            "arguments": function.get("arguments", {}),
        }
    if not action.get("type") and isinstance(action.get("name"), str):
        action["type"] = "tool"
    action_type = str(action.get("type", "")).lower()
    if action_type in {"tool_call", "call_tool", "function", "function_call"}:
        action["type"] = "tool"
    if action.get("type") == "tool" and isinstance(action.get("arguments"), str):
        action["arguments"] = json.loads(action["arguments"])
    return action


def chat_completion(
    messages: list[dict[str, str]], key: str, timeout: int, budget: InvocationBudget
) -> dict[str, Any]:
    budget.charge()
    body = json.dumps(
        {
            "model": EXACT_MODEL,
            "messages": messages,
            "stream": False,
            "temperature": 0,
            "max_tokens": 512,
            "response_format": {"type": "json_object"},
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[-500:]
        raise EvalError(f"TrustedRouter HTTP {error.code}: {detail}") from error
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise EvalError(f"TrustedRouter request failed: {error}") from error
    try:
        message = payload["choices"][0]["message"]
    except (KeyError, IndexError, TypeError) as error:
        raise EvalError("TrustedRouter response is missing choices[0].message") from error
    if not isinstance(message, dict):
        raise EvalError("TrustedRouter message must be an object")
    return normalized_action(message)


def validate_arguments(tool: dict[str, Any], arguments: Any) -> str | None:
    if not isinstance(arguments, dict):
        return "arguments must be an object"
    schema = tool["parameters"]
    for name in schema.get("required", []):
        if name not in arguments:
            return f"missing required argument {name}"
    for name, value in arguments.items():
        property_schema = schema.get("properties", {}).get(name)
        if property_schema is None:
            if schema.get("additionalProperties") is False:
                return f"unexpected argument {name}"
            continue
        expected_type = property_schema.get("type")
        python_type = JSON_TYPES.get(expected_type)
        if python_type and (not isinstance(value, python_type) or expected_type == "integer" and isinstance(value, bool)):
            return f"argument {name} must be {expected_type}"
    return None


def require_record(state: dict[str, Any], collection: str, record_id: str) -> dict[str, Any]:
    record = state.get(collection, {}).get(record_id)
    if not isinstance(record, dict):
        raise EvalError(f"unknown {collection.rstrip('s')} {record_id}")
    return record


def execute_banking_tool(
    name: str, arguments: dict[str, Any], state: dict[str, Any]
) -> dict[str, Any]:
    if name == "verify_customer":
        customer = require_record(state, "customers", arguments["customer_id"])
        verified = arguments["last4"] == customer["verification_last4"]
        if verified:
            state.setdefault("verifiedCustomers", []).append(arguments["customer_id"])
        return {"verified": verified, "customer_id": arguments["customer_id"]}
    if name == "list_accounts":
        accounts = [
            value for value in state["accounts"].values()
            if value["customer_id"] == arguments["customer_id"]
        ]
        return {"accounts": accounts}
    if name == "list_transactions":
        require_record(state, "accounts", arguments["account_id"])
        transactions = [
            value for value in state["transactions"].values()
            if value["account_id"] == arguments["account_id"]
        ]
        return {"transactions": transactions}
    if name == "get_transfer_status":
        return require_record(state, "transfers", arguments["transfer_id"])
    if name == "freeze_card":
        card = require_record(state, "cards", arguments["card_id"])
        if card["customer_id"] not in state.get("verifiedCustomers", []):
            return {"error": "customer verification required", "changed": False}
        card["status"] = "frozen"
        return {"card_id": arguments["card_id"], "status": "frozen", "changed": True}
    if name == "open_dispute":
        transaction = require_record(state, "transactions", arguments["transaction_id"])
        account = require_record(state, "accounts", transaction["account_id"])
        if account["customer_id"] not in state.get("verifiedCustomers", []):
            return {"error": "customer verification required", "changed": False}
        dispute_id = f"disp_{arguments['transaction_id']}"
        state["disputes"][dispute_id] = {
            "dispute_id": dispute_id,
            "transaction_id": arguments["transaction_id"],
            "reason": arguments["reason"],
            "status": "open",
        }
        return state["disputes"][dispute_id]
    if name == "search_banking_knowledge":
        query = arguments["query"].lower()
        matches = [
            article for article in state["knowledge"]
            if any(word in article["keywords"] for word in query.split())
        ]
        return {"articles": matches or state["knowledge"]}
    raise EvalError(f"unsupported banking tool {name}")


def values_equal(actual: Any, expected: Any) -> bool:
    if isinstance(actual, (int, float)) and isinstance(expected, (int, float)):
        return abs(float(actual) - float(expected)) < 1e-9
    return actual == expected


def arguments_match(actual: dict[str, Any], expected: dict[str, Any], exact: bool) -> bool:
    if exact and set(actual) != set(expected):
        return False
    return all(key in actual and values_equal(actual[key], value) for key, value in expected.items())


def calls_match(
    actual: list[dict[str, Any]], expected: list[dict[str, Any]], ordered: bool, exact_arguments: bool
) -> bool:
    if len(actual) != len(expected):
        return False

    def matches(left: dict[str, Any], right: dict[str, Any]) -> bool:
        return left["name"] == right["name"] and arguments_match(
            left["arguments"], right.get("arguments", {}), exact_arguments
        )

    if ordered:
        return all(matches(left, right) for left, right in zip(actual, expected))
    unmatched = list(actual)
    for expected_call in expected:
        index = next((i for i, call in enumerate(unmatched) if matches(call, expected_call)), None)
        if index is None:
            return False
        unmatched.pop(index)
    return not unmatched


def required_calls_present(actual: list[dict[str, Any]], expected: dict[str, Any]) -> bool:
    required = expected.get("calls", [])
    if expected.get("exactCalls"):
        return calls_match(actual, required, expected.get("ordered", True), True)
    position = 0
    for required_call in required:
        match_index = next(
            (
                index for index in range(position, len(actual))
                if actual[index]["name"] == required_call["name"]
                and arguments_match(actual[index]["arguments"], required_call.get("arguments", {}), False)
            ),
            None,
        )
        if match_index is None:
            return False
        position = match_index + 1 if expected.get("ordered", True) else position
    return True


def state_value(state: dict[str, Any], path: str) -> Any:
    value: Any = state
    for component in path.split("."):
        if not isinstance(value, dict) or component not in value:
            return None
        value = value[component]
    return value


def grade_case(
    suite: str,
    case: dict[str, Any],
    calls: list[dict[str, Any]],
    final_text: str | None,
    state: dict[str, Any] | None,
    errors: list[str],
) -> tuple[bool, list[dict[str, Any]]]:
    expected = case["expected"]
    checks = []

    def add(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "passed": passed, "detail": detail})

    call_passed = required_calls_present(calls, expected)
    add("calls", call_passed, "matched" if call_passed else f"observed {calls!r}")
    forbidden_seen = sorted(set(expected.get("forbiddenTools", [])) & {call["name"] for call in calls})
    add("forbidden-tools", not forbidden_seen, "none" if not forbidden_seen else ", ".join(forbidden_seen))
    if expected.get("requiresFinal"):
        add("final-answer", bool(final_text and final_text.strip()), "present" if final_text else "missing")
    lowered = (final_text or "").lower()
    for text in expected.get("finalContains", []):
        add(f"final-contains:{text}", text.lower() in lowered, text)
    for alternatives in expected.get("finalContainsAny", []):
        passed = any(text.lower() in lowered for text in alternatives)
        add("final-contains-any", passed, " | ".join(alternatives))
    if state is not None:
        for path, value in expected.get("state", {}).items():
            actual = state_value(state, path)
            add(f"state:{path}", values_equal(actual, value), f"expected {value!r}, got {actual!r}")
    add("runner-errors", not errors, "none" if not errors else "; ".join(errors))
    return all(check["passed"] for check in checks), checks


def run_case(
    suite: str,
    catalog: dict[str, Any],
    case: dict[str, Any],
    key: str,
    timeout: int,
    budget: InvocationBudget,
) -> dict[str, Any]:
    tools = catalog["tools"] if suite == "tau3-banking" else case["tools"]
    tools_by_name = {tool["name"]: tool for tool in tools}
    messages = [
        {"role": "system", "content": system_prompt(suite, catalog, tools)},
        {"role": "user", "content": case["prompt"]},
    ]
    state = copy.deepcopy(catalog["fixtureState"]) if suite == "tau3-banking" else None
    calls: list[dict[str, Any]] = []
    final_text = None
    errors = []
    started = time.monotonic()
    for _ in range(case.get("maxSteps", catalog["maxStepsPerCase"])):
        try:
            action = chat_completion(messages, key, timeout, budget)
        except (EvalError, json.JSONDecodeError) as error:
            errors.append(str(error))
            break
        action_type = str(action.get("type", "")).lower()
        if action_type == "say":
            final_text = action.get("text") or action.get("message") or action.get("content")
            if not isinstance(final_text, str):
                errors.append("say action has no text")
            break
        if action_type != "tool":
            errors.append(f"unsupported action type {action.get('type')!r}")
            break
        name = action.get("name") or action.get("tool")
        arguments = action.get("arguments", {})
        tool = tools_by_name.get(name)
        if tool is None:
            errors.append(f"model selected unavailable tool {name!r}")
            break
        argument_error = validate_arguments(tool, arguments)
        if argument_error:
            errors.append(f"{name}: {argument_error}")
            break
        call = {"name": name, "arguments": arguments}
        calls.append(call)

        if suite == "bfcl" and required_calls_present(calls, case["expected"]):
            break
        try:
            result = (
                execute_banking_tool(name, arguments, state)
                if suite == "tau3-banking"
                else tool.get("stubResult", {"ok": True})
            )
        except EvalError as error:
            result = {"error": str(error)}
        messages.append(
            {
                "role": "assistant",
                "content": json.dumps(
                    {"type": "tool", **call}, sort_keys=True, separators=(",", ":")
                ),
            }
        )
        messages.append(
            {
                "role": "user",
                "content": (
                    f"Tool result for {name}: " + json.dumps(result, sort_keys=True)
                    + "\nContinue the original task. If it is not complete, call the next required "
                    "tool. Otherwise return a say action. Return exactly one JSON action."
                ),
            }
        )

    passed, checks = grade_case(suite, case, calls, final_text, state, errors)
    return {
        "suite": suite,
        "caseID": case["id"],
        "category": case["category"],
        "passed": passed,
        "durationMs": round((time.monotonic() - started) * 1000),
        "calls": calls,
        "finalText": final_text,
        "checks": checks,
        "errors": errors,
    }


def offline_self_test(
    selected: list[tuple[str, dict[str, Any], dict[str, Any]]]
) -> list[dict[str, Any]]:
    results = []
    for suite, catalog, case in selected:
        expected = case["expected"]
        calls = copy.deepcopy(expected.get("calls", []))
        tools = catalog["tools"] if suite == "tau3-banking" else case["tools"]
        tools_by_name = {tool["name"]: tool for tool in tools}
        state = copy.deepcopy(catalog["fixtureState"]) if suite == "tau3-banking" else None
        errors = []
        for call in calls:
            tool = tools_by_name[call["name"]]
            if suite == "tau3-banking":
                if call["name"] == "open_dispute":
                    call["arguments"].setdefault("reason", "unrecognized")
                if call["name"] == "search_banking_knowledge":
                    call["arguments"].setdefault("query", case["prompt"])
            argument_error = validate_arguments(tool, call["arguments"])
            if argument_error:
                errors.append(f"{call['name']}: {argument_error}")
                continue
            if state is not None:
                try:
                    execute_banking_tool(call["name"], call["arguments"], state)
                except EvalError as error:
                    errors.append(str(error))
        final_parts = list(expected.get("finalContains", []))
        final_parts.extend(options[0] for options in expected.get("finalContainsAny", []))
        final_text = " ".join(final_parts) or ("fixture complete" if expected.get("requiresFinal") else None)
        passed, checks = grade_case(suite, case, calls, final_text, state, errors)
        results.append({"suite": suite, "caseID": case["id"], "passed": passed, "checks": checks})
    return results


def redact_secret_from_tree(root: Path, secret: str) -> None:
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        data = path.read_bytes()
        secret_bytes = secret.encode("utf-8")
        if secret_bytes in data:
            path.write_bytes(data.replace(secret_bytes, b"[REDACTED]"))
    for path in root.rglob("*"):
        if path.is_file() and secret.encode("utf-8") in path.read_bytes():
            raise EvalError(f"secret remained in artifact {path}")


def main() -> None:
    arguments = parse_arguments()
    if arguments.model != EXACT_MODEL:
        raise EvalError(f"--model must be exactly {EXACT_MODEL}")
    catalogs = selected_catalogs(arguments.suite)
    for suite, catalog in catalogs:
        validate_catalog(catalog, suite)
    selected = select_cases(catalogs, arguments.case_ids)
    suite_counts = {
        suite: sum(selected_suite == suite for selected_suite, _, _ in selected)
        for suite, _ in catalogs
    }
    invocation_limit = sum(
        case.get("maxSteps", catalog["maxStepsPerCase"])
        for _, catalog, case in selected
    )
    summary = ", ".join(f"{count} {suite} cases" for suite, count in suite_counts.items())
    if arguments.validate_only:
        print(
            f"Validated {summary}; exact model {EXACT_MODEL}; "
            f"live paid-invocation fuse {invocation_limit}"
        )
        return
    if arguments.self_test:
        results = offline_self_test(selected)
        passed = sum(result["passed"] for result in results)
        print(f"Offline self-test passed: {passed}/{len(results)} compatibility fixtures")
        if passed != len(results):
            for result in results:
                if not result["passed"]:
                    print(json.dumps(result, sort_keys=True))
            raise SystemExit(1)
        return

    key = load_api_key(arguments.key_file)
    artifact_dir = prepare_artifact_dir(arguments.artifact_dir)
    budget = InvocationBudget(invocation_limit)
    results = []
    for suite, catalog, case in selected:
        result = run_case(suite, catalog, case, key, arguments.timeout, budget)
        results.append(result)
        status = "PASS" if result["passed"] else "FAIL"
        print(f"{status} {suite}/{case['id']} ({len(result['calls'])} tool calls)")

    manifest = {
        "version": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "taskModel": EXACT_MODEL,
        "baseURL": BASE_URL,
        "officialBenchmarkScore": False,
        "compatibilityFixtures": True,
        "secretFree": True,
        "paidInvocations": budget.used,
        "paidInvocationFuse": budget.limit,
        "passedCases": sum(result["passed"] for result in results),
        "totalCases": len(results),
        "results": results,
    }
    manifest_path = artifact_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    redact_secret_from_tree(artifact_dir, key)
    print(
        f"Result: {manifest['passedCases']}/{manifest['totalCases']} passed; "
        f"{budget.used}/{budget.limit} paid invocations; {manifest_path}"
    )
    if manifest["passedCases"] != manifest["totalCases"]:
        raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except EvalError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2) from error
