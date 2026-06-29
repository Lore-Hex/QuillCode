#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-packaged-macos-smoke.XXXXXX")"
APP_OUTPUT_DIR="$SMOKE_ROOT/app"
DIRECT_SMOKE_ARTIFACT_DIR="$SMOKE_ROOT/direct-executable"
LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR="$SMOKE_ROOT/launch-services"
CLICK_PROBE_MANIFEST="$SMOKE_ROOT/packaged-click-probes.json"
ARTIFACT_DIR="${QUILLCODE_PACKAGED_MACOS_SMOKE_ARTIFACT_DIR:-}"

cleanup() {
  local status=$?
  set +e

  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    if [[ -n "${INFO_PLIST:-}" && -e "$INFO_PLIST" ]]; then
      cp "$INFO_PLIST" "$ARTIFACT_DIR/Info.plist"
    fi
    if [[ -d "$DIRECT_SMOKE_ARTIFACT_DIR" ]]; then
      rm -rf "$ARTIFACT_DIR/direct-executable"
      cp -R "$DIRECT_SMOKE_ARTIFACT_DIR" "$ARTIFACT_DIR/direct-executable"
    fi
    if [[ -d "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" ]]; then
      rm -rf "$ARTIFACT_DIR/launch-services"
      cp -R "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" "$ARTIFACT_DIR/launch-services"
    fi
    if [[ -e "$CLICK_PROBE_MANIFEST" ]]; then
      cp "$CLICK_PROBE_MANIFEST" "$ARTIFACT_DIR/packaged-click-probes.json"
    fi
    {
      printf 'label=packaged macOS app\n'
      printf 'status=%s\n' "$status"
      printf 'source=%s\n' "$SMOKE_ROOT"
      if [[ -n "${APP_BUNDLE:-}" ]]; then
        printf 'app_bundle=%s\n' "$APP_BUNDLE"
      fi
      printf 'direct_smoke=direct-executable\n'
      printf 'launch_services_smoke=launch-services\n'
      printf 'click_probe_manifest=packaged-click-probes.json\n'
    } > "$ARTIFACT_DIR/manifest.txt"
    echo "QuillCode packaged macOS app smoke artifacts: $ARTIFACT_DIR"
  fi

  rm -rf "$SMOKE_ROOT"
  exit "$status"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "packaged-macos-smoke.sh must run on macOS." >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "==> Building packaged macOS app"
APP_BUNDLE="$("$ROOT_DIR/scripts/build-macos-app.sh" --output "$APP_OUTPUT_DIR")"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/QuillCode"

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Packaged app Info.plist $key expected '$expected' but found '$actual'." >&2
    exit 1
  fi
}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Packaged app bundle was not created: $APP_BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Packaged app executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null
assert_plist_value CFBundleName QuillCode
assert_plist_value CFBundleDisplayName QuillCode
assert_plist_value CFBundleExecutable QuillCode
assert_plist_value CFBundleIdentifier co.lorehex.QuillCode
assert_plist_value CFBundlePackageType APPL
assert_plist_value LSApplicationCategoryType public.app-category.developer-tools
assert_plist_value NSPrincipalClass NSApplication

QUILLCODE_DESKTOP_EXECUTABLE="$APP_EXECUTABLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="$DIRECT_SMOKE_ARTIFACT_DIR" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

QUILLCODE_DESKTOP_APP_BUNDLE="$APP_BUNDLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app Launch Services" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

python3 - "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" "$CLICK_PROBE_MANIFEST" <<'PY'
import json
import sys

direct_report_path, launch_services_report_path, manifest_path = sys.argv[1:4]


def load_report(path):
    with open(path, "r", encoding="utf-8") as report_file:
        return json.load(report_file)


def normalized_probe_contracts(report, label):
    native_targets = report.get("nativeHitTargets")
    if not isinstance(native_targets, dict):
        raise SystemExit(f"{label} report is missing nativeHitTargets")

    click_probes = native_targets.get("clickProbes")
    if not isinstance(click_probes, list) or not click_probes:
        raise SystemExit(f"{label} report is missing clickProbes")

    normalized = []
    for probe in click_probes:
        if not isinstance(probe, dict):
            raise SystemExit(f"{label} report has a malformed click probe: {probe!r}")

        contract_id = probe.get("contractID")
        selector_kind = probe.get("selectorKind")
        selector = probe.get("selector")
        kind = probe.get("kind")
        action = probe.get("action")
        required_min_width = probe.get("requiredMinWidth")
        required_min_height = probe.get("requiredMinHeight")
        sample_points = probe.get("samplePoints")
        if not all(isinstance(value, str) and value.strip() for value in (contract_id, selector_kind, selector, kind, action)):
            raise SystemExit(f"{label} report has an incomplete click probe identity: {probe!r}")
        if not isinstance(required_min_width, (int, float)) or not isinstance(required_min_height, (int, float)):
            raise SystemExit(f"{label} report has an incomplete click probe size contract: {probe!r}")
        if not isinstance(sample_points, list) or not sample_points:
            raise SystemExit(f"{label} report has no click probe sample points for {contract_id}")

        normalized_points = []
        for point in sample_points:
            if not isinstance(point, dict):
                raise SystemExit(f"{label} report has a malformed sample point for {contract_id}: {point!r}")
            name = point.get("name")
            x = point.get("x")
            y = point.get("y")
            if not isinstance(name, str) or not name.strip() or not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
                raise SystemExit(f"{label} report has an incomplete sample point for {contract_id}: {point!r}")
            normalized_points.append({
                "name": name,
                "x": float(x),
                "y": float(y),
            })

        normalized.append({
            "contractID": contract_id,
            "selectorKind": selector_kind,
            "selector": selector,
            "kind": kind,
            "action": action,
            "requiredMinWidth": float(required_min_width),
            "requiredMinHeight": float(required_min_height),
            "samplePoints": sorted(normalized_points, key=lambda point: point["name"]),
        })

    return sorted(normalized, key=lambda probe: probe["contractID"])


direct_report = load_report(direct_report_path)
launch_services_report = load_report(launch_services_report_path)
direct_probe_contracts = normalized_probe_contracts(direct_report, "direct executable")
launch_services_probe_contracts = normalized_probe_contracts(launch_services_report, "Launch Services")

if direct_probe_contracts != launch_services_probe_contracts:
    direct_by_contract_id = {probe["contractID"]: probe for probe in direct_probe_contracts}
    launch_services_by_contract_id = {probe["contractID"]: probe for probe in launch_services_probe_contracts}
    direct_contract_ids = set(direct_by_contract_id)
    launch_services_contract_ids = set(launch_services_by_contract_id)
    missing_from_launch = sorted(direct_contract_ids - launch_services_contract_ids)
    missing_from_direct = sorted(launch_services_contract_ids - direct_contract_ids)
    drifting_contracts = sorted(
        contract_id
        for contract_id in direct_contract_ids & launch_services_contract_ids
        if direct_by_contract_id[contract_id] != launch_services_by_contract_id[contract_id]
    )
    raise SystemExit(
        "Packaged app Launch Services click probes drifted from direct executable probes "
        f"(missingFromLaunch={missing_from_launch}, missingFromDirect={missing_from_direct}, "
        f"driftingContracts={drifting_contracts})"
    )

manifest = {
    "ok": True,
    "directReport": "direct-executable/report.json",
    "launchServicesReport": "launch-services/report.json",
    "launchServicesMatchesDirect": True,
    "clickProbeCount": len(direct_probe_contracts),
    "contractIDs": [probe["contractID"] for probe in direct_probe_contracts],
    "samplePointNames": sorted({
        point["name"]
        for probe in direct_probe_contracts
        for point in probe["samplePoints"]
    }),
}
with open(manifest_path, "w", encoding="utf-8") as manifest_file:
    json.dump(manifest, manifest_file, indent=2, sort_keys=True)
    manifest_file.write("\n")
PY

echo "QuillCode packaged macOS app smoke passed."
