(() => {
  "use strict";

  const releaseAPIURL =
    "https://api.github.com/repos/Lore-Hex/QuillCode/releases/tags/tester-latest";
  const installerURL =
    "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-universal.dmg";

  function readCurrentRelease(release) {
    if (
      !release ||
      release.name !== "Quill Cowork Tester Build" ||
      release.tag_name !== "tester-latest" ||
      release.draft !== false ||
      release.prerelease !== true ||
      !/^[0-9a-f]{40}$/.test(release.target_commitish) ||
      !Array.isArray(release.assets)
    ) {
      return null;
    }

    const installers = release.assets.filter(
      (asset) => asset?.name === "Quill-Cowork-macOS-universal.dmg",
    );
    const installer = installers.length === 1 ? installers[0] : null;
    if (
      !installer ||
      installer.state !== "uploaded" ||
      installer.browser_download_url !== installerURL ||
      !/^sha256:[0-9a-f]{64}$/.test(installer.digest) ||
      !Number.isSafeInteger(installer.size) ||
      installer.size <= 0
    ) {
      return null;
    }

    const updatedAt = new Date(release.updated_at);
    if (!Number.isFinite(updatedAt.getTime())) {
      return null;
    }

    return {
      label: `Updated ${updatedAt.toLocaleDateString("en-US", {
        day: "numeric",
        month: "short",
        year: "numeric",
      })}`,
      installerURL: installer.browser_download_url,
    };
  }

  fetch(releaseAPIURL, {
    cache: "no-store",
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((response) => (response.ok ? response.json() : null))
    .then(readCurrentRelease)
    .then((build) => {
      if (!build) {
        return;
      }

      document.querySelectorAll("[data-download-link]").forEach((link) => {
        link.href = build.installerURL;
      });
      document.querySelectorAll("[data-build-label]").forEach((label) => {
        label.textContent = build.label;
      });
      document.documentElement.dataset.release = "current";
    })
    .catch(() => {
      // Static download links remain complete when live release metadata is unavailable.
    });
})();
