from __future__ import annotations

from dataclasses import dataclass
import json
import subprocess
import tempfile
import time
from typing import Any

from tester_publication.contracts import (
    COMMIT_PATTERN,
    PublicationError,
    ReleaseSnapshot,
    TAG,
    decode_release,
)


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
        raise PublicationError(f"Command failed ({' '.join(arguments)}): {detail}")
    return result.stdout


class PublicationRemote:
    def __init__(self, repository: str, retry_delay_seconds: float) -> None:
        self.repository = repository
        self.retry_delay_seconds = retry_delay_seconds

    def release_endpoint(self) -> str:
        return f"repos/{self.repository}/releases/tags/{TAG}"

    def release_by_id_endpoint(self, identifier: int) -> str:
        return f"repos/{self.repository}/releases/{identifier}"

    def asset_endpoint(self, identifier: int) -> str:
        return f"repos/{self.repository}/releases/assets/{identifier}"

    def get_release(self, *, missing_ok: bool = False) -> ReleaseSnapshot | None:
        result = command_result(["gh", "api", "--method", "GET", self.release_endpoint()])
        if result.exit_code == 0:
            return decode_release(result.stdout)
        if missing_ok and ("HTTP 404" in result.stderr or "Not Found" in result.stderr):
            return None
        detail = result.stderr.strip() or result.stdout.strip() or "no diagnostic output"
        raise PublicationError(f"Could not read {TAG}: {detail}")

    def remote_tag_commit(self, *, missing_ok: bool = False) -> str | None:
        output = run_command(
            ["git", "ls-remote", "--refs", "origin", f"refs/tags/{TAG}"]
        )
        rows = [line.split() for line in output.splitlines() if line.strip()]
        if not rows and missing_ok:
            return None
        if len(rows) != 1 or len(rows[0]) != 2 or rows[0][1] != f"refs/tags/{TAG}":
            raise PublicationError(f"Remote tag {TAG} must resolve to exactly one direct ref.")
        commit = rows[0][0]
        if not COMMIT_PATTERN.fullmatch(commit):
            raise PublicationError(f"Remote tag {TAG} returned an invalid commit.")
        return commit

    def configure_git(self) -> None:
        run_command(["git", "config", "user.name", "github-actions[bot]"])
        run_command(
            [
                "git",
                "config",
                "user.email",
                "41898282+github-actions[bot]@users.noreply.github.com",
            ]
        )

    def force_remote_tag(self, commit: str) -> None:
        run_command(["git", "tag", "-f", TAG, commit])
        run_command(["git", "push", "origin", f"refs/tags/{TAG}", "--force"])

    def delete_remote_tag(self) -> None:
        run_command(["git", "push", "origin", f":refs/tags/{TAG}"])
        command_result(["git", "tag", "-d", TAG])

    def rename_asset(self, identifier: int, name: str) -> None:
        run_command(
            [
                "gh",
                "api",
                "--method",
                "PATCH",
                self.asset_endpoint(identifier),
                "-f",
                f"name={name}",
            ]
        )

    def delete_asset(self, identifier: int) -> None:
        last_error: PublicationError | None = None
        for attempt in range(3):
            try:
                run_command(
                    ["gh", "api", "--method", "DELETE", self.asset_endpoint(identifier)]
                )
                return
            except PublicationError as error:
                last_error = error
                if attempt < 2:
                    time.sleep(self.retry_delay_seconds)
        assert last_error is not None
        raise last_error

    def patch_release(self, snapshot: ReleaseSnapshot, payload: dict[str, Any]) -> None:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", prefix="quill-cowork-release-", suffix=".json"
        ) as handle:
            json.dump(payload, handle, ensure_ascii=True)
            handle.flush()
            run_command(
                [
                    "gh",
                    "api",
                    "--method",
                    "PATCH",
                    self.release_by_id_endpoint(snapshot.identifier),
                    "--input",
                    handle.name,
                ]
            )
