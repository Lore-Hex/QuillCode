(() => {
  "use strict";

  const repositoryURL = "https://github.com/Lore-Hex/QuillCode";
  const installerName = "Quill-Cowork-macOS-universal.dmg";
  const feeds = [
    {
      apiURL: "https://api.github.com/repos/Lore-Hex/QuillCode/releases/latest",
      channel: "stable",
      manifestName: "latest-stable-build.json",
    },
    {
      apiURL:
        "https://api.github.com/repos/Lore-Hex/QuillCode/releases/tags/tester-latest",
      channel: "tester",
      manifestName: "latest-tester-build.json",
    },
  ];

  function uploadedAsset(release, name, expectedURL) {
    const matches = Array.isArray(release?.assets)
      ? release.assets.filter((asset) => asset?.name === name)
      : [];
    const asset = matches.length === 1 ? matches[0] : null;
    if (
      asset?.state !== "uploaded" ||
      asset?.browser_download_url !== expectedURL ||
      !/^sha256:[0-9a-f]{64}$/.test(asset?.digest) ||
      !Number.isSafeInteger(asset?.size) ||
      asset.size <= 0
    ) {
      return null;
    }
    return asset;
  }

  function readCurrentRelease(release, feed) {
    const tag = release?.tag_name;
    const stableTag = /^v[0-9]+\.[0-9]+\.[0-9]+$/.test(tag);
    const testerTitleMatch = /^Quill Cowork Tester ((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)) \(([1-9][0-9]*)\)$/.exec(
      release?.name ?? "",
    );
    const expectedTag = feed.channel === "stable" ? stableTag : tag === "tester-latest";
    const hasExpectedName = feed.channel === "stable"
      ? release?.name === `Quill Cowork ${tag}`
      : testerTitleMatch !== null;
    const expectedPrerelease = feed.channel === "tester";
    const releaseURL = `${repositoryURL}/releases/tag/${tag}`;
    const assetBaseURL = `${repositoryURL}/releases/download/${tag}`;
    const installer = uploadedAsset(
      release,
      installerName,
      `${assetBaseURL}/${installerName}`,
    );
    const manifest = uploadedAsset(
      release,
      feed.manifestName,
      `${assetBaseURL}/${feed.manifestName}`,
    );
    const expectedSigningCopy = feed.channel === "stable"
      ? "Developer ID signed, notarized by Apple, and stapled for normal first launch."
      : "ad-hoc signed and not Apple-notarized.";
    const updatedAt = new Date(release?.updated_at);

    if (
      !expectedTag ||
      !hasExpectedName ||
      release?.html_url !== releaseURL ||
      release?.draft !== false ||
      release?.prerelease !== expectedPrerelease ||
      !/^[0-9a-f]{40}$/.test(release?.target_commitish) ||
      !release?.body?.includes(expectedSigningCopy) ||
      !installer ||
      !manifest ||
      !Number.isFinite(updatedAt.getTime())
    ) {
      return null;
    }

    const isStable = feed.channel === "stable";
    const version = isStable ? tag.slice(1) : testerTitleMatch[1];
    const build = isStable ? null : testerTitleMatch[2];
    const releaseIdentity = isStable ? `Version ${version}` : `${version} (${build})`;
    return {
      build,
      caption: isStable
        ? "The current notarized macOS release. The same workspace handles documents, research, browser tasks, and technical work."
        : "The current macOS tester build. The same workspace handles documents, research, browser tasks, and technical work.",
      channel: feed.channel,
      commit: release.target_commitish,
      installerURL: installer.browser_download_url,
      installGuidance: isStable
        ? "One notarized installer runs natively on Apple silicon and Intel Macs. Move Quill Cowork to Applications, then open it normally."
        : "One installer runs natively on Apple silicon and Intel Macs. After moving the app to Applications, Control-click it and choose Open on first launch. The tester channel is not Apple-notarized yet.",
      label: `${releaseIdentity} · Updated ${updatedAt.toLocaleDateString("en-US", {
        day: "numeric",
        month: "short",
        year: "numeric",
      })}`,
      releaseKind: isStable ? "Stable release" : "Free tester build",
      releaseSection: isStable ? "Stable release" : "Tester release",
      releaseURL,
      version,
    };
  }

  async function fetchRelease(feed) {
    try {
      const response = await fetch(feed.apiURL, {
        cache: "no-store",
        credentials: "omit",
        headers: { Accept: "application/vnd.github+json" },
        referrerPolicy: "no-referrer",
      });
      if (!response.ok) {
        return null;
      }
      return readCurrentRelease(await response.json(), feed);
    } catch {
      return null;
    }
  }

  async function preferredRelease() {
    for (const feed of feeds) {
      const release = await fetchRelease(feed);
      if (release) {
        return release;
      }
    }
    return null;
  }

  preferredRelease().then((release) => {
    if (!release) {
      return;
    }

    document.querySelectorAll("[data-download-link]").forEach((link) => {
      link.href = release.installerURL;
    });
    document.querySelectorAll("[data-release-link]").forEach((link) => {
      link.href = release.releaseURL;
    });
    document.querySelectorAll("[data-build-label]").forEach((label) => {
      label.textContent = release.label;
    });
    document.querySelectorAll("[data-release-kind]").forEach((label) => {
      label.textContent = release.releaseKind;
    });
    document.querySelectorAll("[data-release-section]").forEach((label) => {
      label.textContent = release.releaseSection;
    });
    document.querySelectorAll("[data-install-guidance]").forEach((label) => {
      label.textContent = release.installGuidance;
    });
    document.querySelectorAll("[data-release-caption]").forEach((label) => {
      label.textContent = release.caption;
    });
    document.documentElement.dataset.release = release.channel;
    document.documentElement.dataset.commit = release.commit;
    document.documentElement.dataset.version = release.version;
    if (release.build) {
      document.documentElement.dataset.build = release.build;
    }
  });
})();
