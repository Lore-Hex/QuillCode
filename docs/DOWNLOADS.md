# Downloadable Builds

QuillCode publishes automated tester builds from GitHub Actions.

## Tester Download

Use the moving prerelease:

- [QuillCode Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

That release is refreshed after every successful push to `main`, on the nightly
download-build schedule, and whenever a maintainer runs the **Download Builds**
workflow manually.

Assets:

- `QuillCode-macOS-*.zip`: macOS app bundle.
- `quill-code-macOS-*.tar.gz`: macOS CLI.
- `quill-code-linux-*.tar.gz`: Linux CLI.
- `SHASUMS256.txt`: checksums for all uploaded assets.

The macOS tester app is ad-hoc signed but not notarized yet. Testers may need to
right-click **Open** the first time. Computer Use still requires normal macOS
Screen Recording and Accessibility permissions.

## Versioned Releases

Push a tag such as `v0.1.0` to create a versioned release with the same assets:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Use versioned releases for public announcements. Use `tester-latest` for quick
iteration with early testers.

## Local Packaging

macOS app plus macOS CLI:

```bash
scripts/package-macos-downloads.sh
```

Linux CLI:

```bash
scripts/package-linux-downloads.sh
```

Both scripts write assets under `.build/downloads/.../assets` unless
`QUILLCODE_DOWNLOAD_DIST_DIR` is set.
