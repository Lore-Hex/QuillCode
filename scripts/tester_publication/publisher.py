from __future__ import annotations

from pathlib import Path
import shutil
import tempfile
from typing import Any

from tester_publication.contracts import (
    ASSET_NAME_PATTERN,
    COMMIT_PATTERN,
    LocalAsset,
    PublicationError,
    ReleaseSnapshot,
    RemoteAsset,
    TAG,
    TITLE,
    TRANSACTION_ALIAS_PATTERN,
    ordered_asset_names,
    validate_exact_assets,
    validate_release_metadata,
)
from tester_publication.initial import publish_initial_release
from tester_publication.remote import PublicationRemote, run_command


class TesterReleasePublisher:
    def __init__(
        self,
        repository: str,
        commit: str,
        run_id: str,
        assets: dict[str, LocalAsset],
        notes: str,
        notes_path: Path,
        retry_delay_seconds: float,
    ) -> None:
        self.commit = commit
        self.run_id = run_id
        self.assets = assets
        self.notes = notes
        self.notes_path = notes_path
        self.remote = PublicationRemote(repository, retry_delay_seconds)
        self.candidate_prefix = f"quill-cowork-candidate-{run_id}-"
        self.rollback_prefix = f"quill-cowork-rollback-{run_id}-"
        self.snapshot: ReleaseSnapshot | None = None
        self.previous_tag_commit: str | None = None
        self.candidate_assets: dict[str, RemoteAsset] = {}
        self.committed = False

    def recover_stale_aliases(self, release: ReleaseSnapshot) -> ReleaseSnapshot:
        rollback_groups: dict[str, list[RemoteAsset]] = {}
        candidate_assets: list[tuple[str, RemoteAsset]] = []
        for asset in release.assets.values():
            match = TRANSACTION_ALIAS_PATTERN.fullmatch(asset.name)
            if match is None:
                continue
            kind, _, canonical = match.groups()
            if not ASSET_NAME_PATTERN.fullmatch(canonical):
                raise PublicationError(f"Stale transaction asset has an unsafe name: {asset.name}")
            if kind == "rollback":
                rollback_groups.setdefault(canonical, []).append(asset)
            else:
                candidate_assets.append((canonical, asset))

        if not rollback_groups and not candidate_assets:
            return release
        print("Recovering assets left by an interrupted tester publication.")
        canonical_names = {
            name for name in release.assets if TRANSACTION_ALIAS_PATTERN.fullmatch(name) is None
        }
        for canonical, aliases in sorted(rollback_groups.items()):
            if canonical in canonical_names:
                for asset in aliases:
                    self.remote.delete_asset(asset.identifier)
            elif len(aliases) == 1:
                self.remote.rename_asset(aliases[0].identifier, canonical)
                canonical_names.add(canonical)
            else:
                raise PublicationError(
                    f"Multiple rollback assets exist for missing canonical asset {canonical}."
                )
        for canonical, asset in candidate_assets:
            if canonical not in canonical_names:
                raise PublicationError(
                    f"Candidate asset {asset.name} has no verified canonical or rollback copy."
                )
            self.remote.delete_asset(asset.identifier)

        recovered = self.remote.get_release()
        assert recovered is not None
        leftovers = [
            name for name in recovered.assets if TRANSACTION_ALIAS_PATTERN.fullmatch(name)
        ]
        if leftovers:
            raise PublicationError("Interrupted publication aliases remain after recovery.")
        return recovered

    def validate_existing_release(self, release: ReleaseSnapshot) -> None:
        if release.tag_name != TAG:
            raise PublicationError(f"Existing tester release must use tag {TAG}.")
        if release.draft or not release.prerelease or release.immutable:
            raise PublicationError(
                "Existing tester release must be a mutable, published prerelease."
            )
        if not release.assets:
            raise PublicationError("Existing tester release must contain rollback-safe assets.")
        if any(TRANSACTION_ALIAS_PATTERN.fullmatch(name) for name in release.assets):
            raise PublicationError("Existing tester release still contains transaction aliases.")

    def upload_candidates(self, staging_directory: Path) -> None:
        for canonical in ordered_asset_names(self.assets):
            local = self.assets[canonical]
            candidate_name = f"{self.candidate_prefix}{canonical}"
            if len(candidate_name) > 240:
                raise PublicationError(f"Transaction asset name is too long: {candidate_name}")
            candidate_path = staging_directory / candidate_name
            shutil.copyfile(local.path, candidate_path)
            run_command(
                [
                    "gh",
                    "release",
                    "upload",
                    TAG,
                    str(candidate_path),
                    "--repo",
                    self.remote.repository,
                ]
            )

        staged_release = self.remote.get_release()
        assert staged_release is not None
        for canonical, local in self.assets.items():
            candidate_name = f"{self.candidate_prefix}{canonical}"
            candidate = staged_release.assets.get(candidate_name)
            if candidate is None:
                raise PublicationError(f"GitHub did not retain staged asset {candidate_name}.")
            if (
                candidate.state != "uploaded"
                or candidate.size != local.size
                or candidate.digest != local.digest
            ):
                raise PublicationError(f"GitHub staged asset metadata disagrees for {canonical}.")
            self.candidate_assets[canonical] = candidate

    def swap_assets(self) -> None:
        assert self.snapshot is not None
        for canonical in ordered_asset_names(self.assets):
            previous = self.snapshot.assets.get(canonical)
            if previous is not None:
                self.remote.rename_asset(
                    previous.identifier,
                    f"{self.rollback_prefix}{canonical}",
                )
            self.remote.rename_asset(self.candidate_assets[canonical].identifier, canonical)

        obsolete = sorted(set(self.snapshot.assets) - set(self.assets))
        for canonical in obsolete:
            previous = self.snapshot.assets[canonical]
            self.remote.rename_asset(
                previous.identifier,
                f"{self.rollback_prefix}{canonical}",
            )

    def validate_swapped_assets(self) -> None:
        assert self.snapshot is not None
        release = self.remote.get_release()
        assert release is not None
        expected_names = set(self.assets)
        expected_names.update(
            f"{self.rollback_prefix}{name}" for name in self.snapshot.assets
        )
        if set(release.assets) != expected_names:
            raise PublicationError("Swapped tester asset inventory is incomplete or unexpected.")
        for name, local in self.assets.items():
            remote = release.assets[name]
            if remote.state != "uploaded" or remote.size != local.size or remote.digest != local.digest:
                raise PublicationError(f"Canonical GitHub asset metadata disagrees for {name}.")

    def publication_payload(self) -> dict[str, Any]:
        return {
            "tag_name": TAG,
            "target_commitish": self.commit,
            "name": TITLE,
            "body": self.notes,
            "draft": False,
            "prerelease": True,
            "make_latest": "false",
        }

    def restore_payload(self) -> dict[str, Any]:
        assert self.snapshot is not None
        return {
            "tag_name": self.snapshot.tag_name,
            "target_commitish": self.snapshot.target_commitish,
            "name": self.snapshot.name,
            "body": self.snapshot.body,
            "draft": self.snapshot.draft,
            "prerelease": self.snapshot.prerelease,
            "make_latest": "false",
        }

    def rollback_existing(self) -> None:
        assert self.snapshot is not None
        assert self.previous_tag_commit is not None
        errors: list[str] = []

        try:
            current = self.remote.get_release()
            assert current is not None
            candidate_ids = {asset.identifier for asset in self.candidate_assets.values()}
            candidate_ids.update(
                asset.identifier
                for asset in current.assets.values()
                if asset.name.startswith(self.candidate_prefix)
            )
            current_ids = {asset.identifier for asset in current.assets.values()}
            for identifier in sorted(candidate_ids & current_ids):
                self.remote.delete_asset(identifier)
        except (PublicationError, AssertionError) as error:
            errors.append(str(error))

        try:
            current = self.remote.get_release()
            assert current is not None
            by_identifier = {asset.identifier: asset for asset in current.assets.values()}
            for canonical, previous in self.snapshot.assets.items():
                live = by_identifier.get(previous.identifier)
                if live is None:
                    raise PublicationError(f"Rollback asset disappeared: {canonical}")
                if live.name != canonical:
                    self.remote.rename_asset(previous.identifier, canonical)
        except (PublicationError, AssertionError) as error:
            errors.append(str(error))

        try:
            self.remote.patch_release(self.snapshot, self.restore_payload())
        except PublicationError as error:
            errors.append(str(error))
        try:
            self.remote.force_remote_tag(self.previous_tag_commit)
        except PublicationError as error:
            errors.append(str(error))

        if not errors:
            try:
                self.validate_restored_snapshot()
            except (PublicationError, AssertionError) as error:
                errors.append(str(error))
        if errors:
            raise PublicationError("Tester publication rollback was incomplete: " + " | ".join(errors))
        print("Restored the previous tester release after publication failure.")

    def validate_restored_snapshot(self) -> None:
        assert self.snapshot is not None
        assert self.previous_tag_commit is not None
        restored = self.remote.get_release()
        assert restored is not None
        if (
            restored.target_commitish != self.snapshot.target_commitish
            or restored.name != self.snapshot.name
            or restored.body != self.snapshot.body
            or restored.draft != self.snapshot.draft
            or restored.prerelease != self.snapshot.prerelease
        ):
            raise PublicationError("Restored release metadata does not match its snapshot.")
        if set(restored.assets) != set(self.snapshot.assets):
            raise PublicationError("Restored release asset inventory does not match its snapshot.")
        for name, previous in self.snapshot.assets.items():
            live = restored.assets[name]
            if live.size != previous.size or live.digest != previous.digest:
                raise PublicationError(f"Restored release asset metadata differs for {name}.")
        if self.remote.remote_tag_commit() != self.previous_tag_commit:
            raise PublicationError("Restored tester tag does not match its snapshot.")

    def cleanup_rollback_assets(self) -> None:
        assert self.snapshot is not None
        for previous in self.snapshot.assets.values():
            self.remote.delete_asset(previous.identifier)

    def publish_existing(self, release: ReleaseSnapshot) -> None:
        self.validate_existing_release(release)
        self.snapshot = release
        self.previous_tag_commit = self.remote.remote_tag_commit()
        assert self.previous_tag_commit is not None
        if (
            COMMIT_PATTERN.fullmatch(release.target_commitish)
            and self.previous_tag_commit != release.target_commitish
        ):
            raise PublicationError("Existing tester release target and remote tag disagree.")
        self.remote.configure_git()

        try:
            with tempfile.TemporaryDirectory(prefix="quill-cowork-publication-") as directory:
                self.upload_candidates(Path(directory))
            self.swap_assets()
            self.validate_swapped_assets()
            self.remote.patch_release(release, self.publication_payload())
            self.remote.force_remote_tag(self.commit)

            published = self.remote.get_release()
            assert published is not None
            validate_release_metadata(published, self.commit, self.notes)
            if self.remote.remote_tag_commit() != self.commit:
                raise PublicationError("Published tester tag does not match the requested commit.")
            self.committed = True
            self.cleanup_rollback_assets()

            final_release = self.remote.get_release()
            assert final_release is not None
            validate_release_metadata(final_release, self.commit, self.notes)
            validate_exact_assets(final_release, self.assets)
        except Exception as error:
            if not self.committed:
                try:
                    self.rollback_existing()
                except PublicationError as rollback_error:
                    raise PublicationError(f"{error} | {rollback_error}") from error
            raise
        print(f"Published transactional tester release {self.commit}.")

    def publish(self) -> None:
        release = self.remote.get_release(missing_ok=True)
        if release is None:
            publish_initial_release(
                self.remote,
                self.commit,
                self.assets,
                self.notes,
                self.notes_path,
            )
            return
        recovered = self.recover_stale_aliases(release)
        self.publish_existing(recovered)
