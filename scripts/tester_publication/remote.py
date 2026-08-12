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


REMOTE_ATTEMPTS = 5
MAX_RETRY_DELAY_SECONDS = 30.0
TRANSIENT_REMOTE_DIAGNOSTICS = (
    "certificate signed by unknown authority",
    "certificate is not valid",
    "connection refused",
    "connection reset",
    "could not resolve host",
    "gateway timeout",
    "http 429",
    "http 500",
    "http 502",
    "http 503",
    "http 504",
    "i/o timeout",
    "network is unreachable",
    "remote end hung up",
    "secondary rate limit",
    "service unavailable",
    "server error",
    "temporary failure",
    "timed out",
    "tls:",
    "unexpected eof",
    "x509:",
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
        raise command_error(arguments, result)
    return result.stdout


def command_error(arguments: list[str], result: CommandResult) -> PublicationError:
    detail = result.stderr.strip() or result.stdout.strip() or "no diagnostic output"
    return PublicationError(f"Command failed ({' '.join(arguments)}): {detail}")


def is_transient_remote_failure(result: CommandResult) -> bool:
    diagnostic = f"{result.stderr}\n{result.stdout}".lower()
    return any(fragment in diagnostic for fragment in TRANSIENT_REMOTE_DIAGNOSTICS)


def is_not_found(result: CommandResult) -> bool:
    diagnostic = f"{result.stderr}\n{result.stdout}".lower()
    return "http 404" in diagnostic or "not found" in diagnostic


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

    def wait_before_retry(self, attempt: int) -> None:
        delay = min(
            self.retry_delay_seconds * (2**attempt),
            MAX_RETRY_DELAY_SECONDS,
        )
        if delay > 0:
            time.sleep(delay)

    def run_idempotent_remote_command(
        self,
        arguments: list[str],
        *,
        missing_ok: bool = False,
    ) -> str:
        for attempt in range(REMOTE_ATTEMPTS):
            result = command_result(arguments)
            if result.exit_code == 0:
                return result.stdout
            if missing_ok and is_not_found(result):
                return ""
            if attempt + 1 == REMOTE_ATTEMPTS or not is_transient_remote_failure(result):
                raise command_error(arguments, result)
            self.wait_before_retry(attempt)
        raise AssertionError("Remote retry loop must return or raise.")

    def get_release(self, *, missing_ok: bool = False) -> ReleaseSnapshot | None:
        arguments = ["gh", "api", "--method", "GET", self.release_endpoint()]
        for attempt in range(REMOTE_ATTEMPTS):
            result = command_result(arguments)
            if result.exit_code == 0:
                return decode_release(result.stdout)
            if missing_ok and is_not_found(result):
                return None
            if attempt + 1 == REMOTE_ATTEMPTS or not is_transient_remote_failure(result):
                detail = result.stderr.strip() or result.stdout.strip() or "no diagnostic output"
                raise PublicationError(f"Could not read {TAG}: {detail}")
            self.wait_before_retry(attempt)
        raise AssertionError("Release retry loop must return or raise.")

    def upload_asset(self, path: str, expected_size: int, expected_digest: str) -> None:
        arguments = [
            "gh",
            "release",
            "upload",
            TAG,
            path,
            "--repo",
            self.repository,
        ]
        expected_name = path.rsplit("/", 1)[-1]
        for attempt in range(REMOTE_ATTEMPTS):
            result = command_result(arguments)
            if result.exit_code == 0:
                return

            probe_error: PublicationError | None = None
            release: ReleaseSnapshot | None = None
            try:
                release = self.get_release()
            except PublicationError as error:
                probe_error = error
            if release is not None:
                remote = release.assets.get(expected_name)
                if remote is not None:
                    if (
                        remote.state == "uploaded"
                        and remote.size == expected_size
                        and remote.digest == expected_digest
                    ):
                        return
                    raise PublicationError(
                        f"GitHub retained conflicting metadata for staged asset {expected_name}."
                    )

            diagnostic = f"{result.stderr}\n{result.stdout}".lower()
            release_temporarily_missing = release is not None and "release not found" in diagnostic
            retryable = is_transient_remote_failure(result) or release_temporarily_missing
            if attempt + 1 < REMOTE_ATTEMPTS and retryable:
                self.wait_before_retry(attempt)
                continue
            error = command_error(arguments, result)
            if probe_error is not None:
                raise PublicationError(f"{error} | Upload state probe failed: {probe_error}")
            raise error
        raise AssertionError("Upload retry loop must return or raise.")

    def remote_tag_commit(self, *, missing_ok: bool = False) -> str | None:
        output = self.run_idempotent_remote_command(
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
        self.run_idempotent_remote_command(
            ["git", "push", "origin", f"refs/tags/{TAG}", "--force"]
        )

    def delete_remote_tag(self) -> None:
        self.run_idempotent_remote_command(
            ["git", "push", "origin", f":refs/tags/{TAG}"],
            missing_ok=True,
        )
        command_result(["git", "tag", "-d", TAG])

    def rename_asset(self, identifier: int, name: str) -> None:
        self.run_idempotent_remote_command(
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
        arguments = ["gh", "api", "--method", "DELETE", self.asset_endpoint(identifier)]
        for attempt in range(REMOTE_ATTEMPTS):
            result = command_result(arguments)
            if result.exit_code == 0 or is_not_found(result):
                return
            if attempt + 1 == REMOTE_ATTEMPTS:
                raise command_error(arguments, result)
            self.wait_before_retry(attempt)
        raise AssertionError("Delete retry loop must return or raise.")

    def patch_release(self, snapshot: ReleaseSnapshot, payload: dict[str, Any]) -> None:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", prefix="quill-cowork-release-", suffix=".json"
        ) as handle:
            json.dump(payload, handle, ensure_ascii=True)
            handle.flush()
            self.run_idempotent_remote_command(
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
