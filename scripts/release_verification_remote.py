"""Bounded GitHub transport for published release verification."""

from __future__ import annotations

import hashlib
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from pathlib import Path
from typing import Any, TypeVar
from urllib.parse import quote

from release_verification_contract import (
    API_BYTE_LIMIT,
    SHA_PATTERN,
    VerificationError,
    load_json_bytes,
)


Result = TypeVar("Result")


def fetch_bytes(
    url: str,
    byte_limit: int,
    *,
    token: str | None = None,
    accept: str = "application/octet-stream",
) -> bytes:
    headers = {
        "Accept": accept,
        "User-Agent": "Quill-Cowork-Release-Verifier/1",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise VerificationError(f"GET {url} returned HTTP {response.status}")
            length = response.headers.get("Content-Length")
            if length and int(length) > byte_limit:
                raise VerificationError(
                    f"GET {url} exceeds its {byte_limit}-byte limit"
                )
            data = response.read(byte_limit + 1)
    except VerificationError:
        raise
    except urllib.error.HTTPError as error:
        raise VerificationError(f"GET {url} returned HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise VerificationError(f"GET {url} failed: {error.reason}") from error
    except (OSError, ValueError) as error:
        raise VerificationError(f"GET {url} failed: {error}") from error
    if len(data) > byte_limit:
        raise VerificationError(f"GET {url} exceeds its {byte_limit}-byte limit")
    return data


def api_json(repo: str, path: str, token: str | None) -> dict[str, Any]:
    url = f"https://api.github.com/repos/{repo}/{path}"
    return load_json_bytes(
        fetch_bytes(
            url,
            API_BYTE_LIMIT,
            token=token,
            accept="application/vnd.github+json",
        ),
        url,
    )


def resolve_tag_commit(repo: str, tag: str, token: str | None) -> str:
    reference = api_json(repo, f"git/ref/tags/{quote(tag, safe='')}", token)
    target = reference.get("object")
    for _ in range(5):
        if not isinstance(target, dict):
            break
        target_type = target.get("type")
        sha = target.get("sha")
        if not isinstance(sha, str) or not SHA_PATTERN.fullmatch(sha):
            break
        if target_type == "commit":
            return sha
        if target_type != "tag":
            break
        tag_object = api_json(repo, f"git/tags/{sha}", token)
        target = tag_object.get("object")
    raise VerificationError(f"release tag {tag!r} does not resolve to a commit")


def download_asset(url: str, destination: Path, size: int, digest: str) -> None:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/octet-stream",
            "User-Agent": "Quill-Cowork-Release-Verifier/1",
        },
    )
    temporary = destination.with_suffix(destination.suffix + ".part")
    try:
        with urllib.request.urlopen(request, timeout=60) as response, temporary.open(
            "xb"
        ) as output:
            if response.status != 200 or not response.geturl().lower().startswith(
                "https://"
            ):
                raise VerificationError(
                    f"download for {destination.name!r} returned an invalid response"
                )
            response_length = response.headers.get("Content-Length")
            if response_length and int(response_length) != size:
                raise VerificationError(
                    f"download for {destination.name!r} reported the wrong size"
                )
            hasher = hashlib.sha256()
            downloaded = 0
            while chunk := response.read(1024 * 1024):
                downloaded += len(chunk)
                if downloaded > size:
                    raise VerificationError(
                        f"download for {destination.name!r} exceeded its size"
                    )
                output.write(chunk)
                hasher.update(chunk)
        if downloaded != size or hasher.hexdigest() != digest:
            raise VerificationError(
                f"download for {destination.name!r} failed integrity verification"
            )
        temporary.replace(destination)
    except VerificationError:
        temporary.unlink(missing_ok=True)
        raise
    except urllib.error.HTTPError as error:
        temporary.unlink(missing_ok=True)
        raise VerificationError(
            f"download for {destination.name!r} returned HTTP {error.code}"
        ) from error
    except urllib.error.URLError as error:
        temporary.unlink(missing_ok=True)
        raise VerificationError(
            f"download for {destination.name!r} failed: {error.reason}"
        ) from error
    except (OSError, ValueError) as error:
        temporary.unlink(missing_ok=True)
        raise VerificationError(
            f"download for {destination.name!r} failed: {error}"
        ) from error


def retry(
    operation: Callable[[], Result],
    *,
    attempts: int,
    delay: float,
    label: str,
) -> Result:
    last_error: VerificationError | None = None
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except VerificationError as error:
            last_error = error
            if attempt < attempts:
                print(
                    f"{label} attempt {attempt} failed: {error}; retrying",
                    flush=True,
                )
                time.sleep(delay)
    if last_error is None:
        raise VerificationError(f"{label} did not run")
    raise last_error
