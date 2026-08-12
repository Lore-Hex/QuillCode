from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import subprocess

from updater_source_capture.contracts import CaptureError, Release, decode_release


@dataclass(frozen=True)
class CommandResult:
    exit_code: int
    stdout: str
    stderr: str


def command_result(arguments: list[str]) -> CommandResult:
    completed = subprocess.run(
        arguments,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return CommandResult(completed.returncode, completed.stdout, completed.stderr)


def run_command(arguments: list[str]) -> str:
    result = command_result(arguments)
    if result.exit_code != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "no diagnostic output"
        raise CaptureError(f"Command failed ({' '.join(arguments)}): {detail}")
    return result.stdout


class CaptureRemote:
    def __init__(self, repository: str, channel: str) -> None:
        self.repository = repository
        self.channel = channel

    def release_endpoint(self) -> str:
        if self.channel == "tester":
            return f"repos/{self.repository}/releases/tags/tester-latest"
        return f"repos/{self.repository}/releases/latest"

    def get_release(self, *, missing_ok: bool) -> Release | None:
        result = command_result(["gh", "api", "--method", "GET", self.release_endpoint()])
        if result.exit_code == 0:
            return decode_release(result.stdout, self.channel)
        if missing_ok and ("HTTP 404" in result.stderr or "Not Found" in result.stderr):
            return None
        detail = result.stderr.strip() or result.stdout.strip() or "no diagnostic output"
        raise CaptureError(f"Could not read the published {self.channel} source release: {detail}")

    def download_asset(self, release: Release, name: str, directory: Path) -> Path:
        run_command(
            [
                "gh",
                "release",
                "download",
                release.tag,
                "--repo",
                self.repository,
                "--pattern",
                name,
                "--dir",
                str(directory),
            ]
        )
        path = directory / name
        if not path.is_file() or path.is_symlink():
            raise CaptureError(f"GitHub did not download exactly one regular asset named {name}.")
        return path
