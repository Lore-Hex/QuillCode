#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const testRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(testRoot, "../..");
const source = fs.readFileSync(
  path.join(repositoryRoot, "website/static/site.js"),
  "utf8",
);
const repositoryURL = "https://github.com/Lore-Hex/QuillCode";
const stableAPIURL = "https://api.github.com/repos/Lore-Hex/QuillCode/releases/latest";
const testerAPIURL =
  "https://api.github.com/repos/Lore-Hex/QuillCode/releases/tags/tester-latest";
const testerInstallerURL =
  `${repositoryURL}/releases/download/tester-latest/Quill-Cowork-macOS-universal.dmg`;
const testerReleaseURL = `${repositoryURL}/releases/tag/tester-latest`;

function releaseFixture(channel, overrides = {}) {
  const isStable = channel === "stable";
  const version = isStable ? "1.2.3" : "0.1.0";
  const build = "772";
  const tag = isStable ? `v${version}` : "tester-latest";
  const assetURL = (name) => `${repositoryURL}/releases/download/${tag}/${name}`;
  return {
    name: isStable
      ? `Quill Cowork ${tag}`
      : `Quill Cowork Tester ${version} (${build})`,
    tag_name: tag,
    html_url: `${repositoryURL}/releases/tag/${tag}`,
    draft: false,
    prerelease: !isStable,
    target_commitish: "d624fb2b11bd177eb19fbb9ef9c341dc2b52f278",
    updated_at: "2026-08-13T08:48:58Z",
    body: isStable
      ? "This build is Developer ID signed, notarized by Apple, and stapled for normal first launch."
      : "This tester build is ad-hoc signed and not Apple-notarized.",
    assets: [
      {
        name: "Quill-Cowork-macOS-universal.dmg",
        state: "uploaded",
        browser_download_url: assetURL("Quill-Cowork-macOS-universal.dmg"),
        digest: `sha256:${"a".repeat(64)}`,
        size: 29_252_809,
      },
      {
        name: isStable ? "latest-stable-build.json" : "latest-tester-build.json",
        state: "uploaded",
        browser_download_url: assetURL(
          isStable ? "latest-stable-build.json" : "latest-tester-build.json",
        ),
        digest: `sha256:${"b".repeat(64)}`,
        size: 7_803,
      },
    ],
    ...overrides,
  };
}

function elements(count, textContent = "") {
  return Array.from({ length: count }, () => ({ textContent }));
}

async function runSiteScript(responses = new Map()) {
  const downloadLinks = Array.from({ length: 3 }, () => ({ href: testerInstallerURL }));
  const releaseLinks = Array.from({ length: 3 }, () => ({ href: testerReleaseURL }));
  const labels = elements(2, "Latest tester release");
  const releaseKinds = elements(1, "Free tester build");
  const releaseSections = elements(1, "Tester release");
  const guidance = elements(1, "tester guidance");
  const captions = elements(1, "tester caption");
  const fetches = [];
  const selectorResults = new Map([
    ["[data-download-link]", downloadLinks],
    ["[data-release-link]", releaseLinks],
    ["[data-build-label]", labels],
    ["[data-release-kind]", releaseKinds],
    ["[data-release-section]", releaseSections],
    ["[data-install-guidance]", guidance],
    ["[data-release-caption]", captions],
  ]);
  const document = {
    documentElement: { dataset: {} },
    querySelectorAll(selector) {
      const result = selectorResults.get(selector);
      if (!result) {
        throw new Error(`Unexpected selector: ${selector}`);
      }
      return result;
    },
  };
  const fetch = async (url, options) => {
    fetches.push({ url, options });
    const response = responses.get(url);
    if (response instanceof Error) {
      throw response;
    }
    if (!response) {
      return { ok: false, json: async () => null };
    }
    return {
      ok: response.ok ?? true,
      json: async () => response.body,
    };
  };

  vm.runInNewContext(source, { document, fetch }, { filename: "site.js" });
  for (let index = 0; index < 5; index += 1) {
    await new Promise((resolve) => setImmediate(resolve));
  }
  return {
    captions,
    document,
    downloadLinks,
    fetches,
    guidance,
    labels,
    releaseKinds,
    releaseLinks,
    releaseSections,
  };
}

const stableRelease = releaseFixture("stable");
const stable = await runSiteScript(new Map([
  [stableAPIURL, { body: stableRelease }],
]));
assert.deepEqual(stable.fetches.map(({ url }) => url), [stableAPIURL]);
assert.equal(stable.fetches[0].options.cache, "no-store");
assert.equal(stable.fetches[0].options.credentials, "omit");
assert.equal(stable.fetches[0].options.headers.Accept, "application/vnd.github+json");
assert.equal(stable.fetches[0].options.referrerPolicy, "no-referrer");
assert.equal(stable.document.documentElement.dataset.release, "stable");
assert.equal(
  stable.document.documentElement.dataset.commit,
  stableRelease.target_commitish,
);
assert.equal(stable.document.documentElement.dataset.version, "1.2.3");
assert.equal(stable.document.documentElement.dataset.build, undefined);
assert.ok(stable.labels.every(({ textContent }) => textContent === "Version 1.2.3 · Updated Aug 13, 2026"));
assert.ok(stable.releaseKinds.every(({ textContent }) => textContent === "Stable release"));
assert.ok(stable.releaseSections.every(({ textContent }) => textContent === "Stable release"));
assert.ok(stable.guidance.every(({ textContent }) => textContent.includes("notarized")));
assert.ok(stable.captions.every(({ textContent }) => textContent.includes("notarized")));
assert.ok(stable.downloadLinks.every(({ href }) => href === stableRelease.assets[0].browser_download_url));
assert.ok(stable.releaseLinks.every(({ href }) => href === stableRelease.html_url));

const testerRelease = releaseFixture("tester");
const tester = await runSiteScript(new Map([
  [stableAPIURL, { ok: false }],
  [testerAPIURL, { body: testerRelease }],
]));
assert.deepEqual(
  tester.fetches.map(({ url }) => url),
  [stableAPIURL, testerAPIURL],
);
assert.equal(tester.document.documentElement.dataset.release, "tester");
assert.equal(
  tester.document.documentElement.dataset.commit,
  testerRelease.target_commitish,
);
assert.equal(tester.document.documentElement.dataset.version, "0.1.0");
assert.equal(tester.document.documentElement.dataset.build, "772");
assert.ok(tester.labels.every(({ textContent }) => textContent === "0.1.0 (772) · Updated Aug 13, 2026"));
assert.ok(tester.releaseKinds.every(({ textContent }) => textContent === "Free tester build"));
assert.ok(tester.guidance.every(({ textContent }) => textContent.includes("Open Anyway")));
assert.ok(tester.downloadLinks.every(({ href }) => href === testerInstallerURL));
assert.ok(tester.releaseLinks.every(({ href }) => href === testerReleaseURL));

const unsignedStable = releaseFixture("stable", {
  body: "This build is ad-hoc signed and not Apple-notarized.",
});
const stableFallback = await runSiteScript(new Map([
  [stableAPIURL, { body: unsignedStable }],
  [testerAPIURL, { body: testerRelease }],
]));
assert.equal(stableFallback.document.documentElement.dataset.release, "tester");

const missingManifest = releaseFixture("stable");
missingManifest.assets = [missingManifest.assets[0]];
const assetFallback = await runSiteScript(new Map([
  [stableAPIURL, { body: missingManifest }],
  [testerAPIURL, { body: testerRelease }],
]));
assert.equal(assetFallback.document.documentElement.dataset.release, "tester");

const malformedTesterTitle = releaseFixture("tester", {
  name: "Quill Cowork Tester Build",
});
const titleFallback = await runSiteScript(new Map([
  [stableAPIURL, { ok: false }],
  [testerAPIURL, { body: malformedTesterTitle }],
]));
assert.equal(titleFallback.document.documentElement.dataset.release, undefined);
assert.equal(titleFallback.document.documentElement.dataset.build, undefined);

const unavailable = await runSiteScript(new Map([
  [stableAPIURL, new Error("offline")],
  [testerAPIURL, new Error("offline")],
]));
assert.equal(unavailable.document.documentElement.dataset.release, undefined);
assert.equal(unavailable.document.documentElement.dataset.commit, undefined);
assert.ok(
  unavailable.labels.every(({ textContent }) => textContent === "Latest tester release"),
);
assert.ok(unavailable.downloadLinks.every(({ href }) => href === testerInstallerURL));
assert.ok(unavailable.releaseLinks.every(({ href }) => href === testerReleaseURL));

console.log("Verified Quill Cowork website stable-first release enhancement");
