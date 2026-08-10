from __future__ import annotations

from pathlib import Path

from tester_publication.contracts import (
    LocalAsset,
    PublicationError,
    TAG,
    TITLE,
    ordered_asset_names,
    validate_exact_assets,
    validate_release_metadata,
)
from tester_publication.remote import PublicationRemote, command_result, run_command


def publish_initial_release(
    remote: PublicationRemote,
    commit: str,
    assets: dict[str, LocalAsset],
    notes: str,
    notes_path: Path,
) -> None:
    previous_tag_commit = remote.remote_tag_commit(missing_ok=True)
    remote.configure_git()
    created_release = False
    try:
        remote.force_remote_tag(commit)
        run_command(
            [
                "gh",
                "release",
                "create",
                TAG,
                "--repo",
                remote.repository,
                "--draft",
                "--title",
                TITLE,
                "--notes-file",
                str(notes_path),
                "--target",
                commit,
                "--latest=false",
            ]
        )
        created_release = True
        for name in ordered_asset_names(assets):
            run_command(
                [
                    "gh",
                    "release",
                    "upload",
                    TAG,
                    str(assets[name].path),
                    "--repo",
                    remote.repository,
                ]
            )
        run_command(
            [
                "gh",
                "release",
                "edit",
                TAG,
                "--repo",
                remote.repository,
                "--draft=false",
                "--prerelease",
                "--latest=false",
                "--title",
                TITLE,
                "--notes-file",
                str(notes_path),
                "--target",
                commit,
            ]
        )
        release = remote.get_release()
        assert release is not None
        validate_release_metadata(release, commit, notes)
        validate_exact_assets(release, assets)
    except Exception as error:
        if created_release:
            command_result(
                ["gh", "release", "delete", TAG, "--repo", remote.repository, "--yes"]
            )
        try:
            if previous_tag_commit is None:
                remote.delete_remote_tag()
            else:
                remote.force_remote_tag(previous_tag_commit)
        except PublicationError as rollback_error:
            raise PublicationError(
                f"{error} | Initial release rollback failed: {rollback_error}"
            ) from error
        raise
    print(f"Published initial tester release {commit}.")
