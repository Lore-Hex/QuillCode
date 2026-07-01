"""Shared native click-probe validation constants."""

from __future__ import annotations

MINIMUM_HIT_TARGET = 44
MINIMUM_TARGET_CLEARANCE = 8
MINIMUM_WINDOW_SCREENSHOT_BYTES = 4096
REQUIRED_WINDOW_COMMAND_IDS = [
    "new-chat",
    "command-palette",
    "keyboard-shortcuts",
    "settings",
    "toggle-terminal",
    "toggle-browser",
    "stop-all",
    "disconnect-all",
]
REQUIRED_WINDOW_STARTER_ACTION_IDS = [
    "review-changes",
    "run-tests",
    "explain-project",
]
REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS = [
    "command.new-chat",
    "command.search",
    "command.settings",
    "command.toggle-automations",
    "command.toggle-extensions",
    "composer.input",
    "composer.mode-picker",
    "composer.model-picker",
    "composer.send",
    "sidebar.tools-menu",
    "top-bar.overflow",
]
REQUIRED_LIVE_ACCESSIBILITY_ACTIVATION_CONTRACT_IDS = [
    "command.settings",
    "command.toggle-automations",
    "command.toggle-extensions",
]
EXPECTED_SAMPLE_POINTS = {
    "center": (0.5, 0.5),
    "leading-edge": (0.08, 0.5),
    "leading-interior": (0.18, 0.5),
    "trailing-edge": (0.92, 0.5),
    "trailing-interior": (0.82, 0.5),
    "top-edge": (0.5, 0.08),
    "top-interior": (0.5, 0.18),
    "bottom-edge": (0.5, 0.92),
    "bottom-interior": (0.5, 0.82),
}
