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
const installerURL =
  "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-universal.dmg";
const releaseAPIURL =
  "https://api.github.com/repos/Lore-Hex/QuillCode/releases/tags/tester-latest";

function releaseFixture(overrides = {}) {
  return {
    name: "Quill Cowork Tester Build",
    tag_name: "tester-latest",
    draft: false,
    prerelease: true,
    target_commitish: "d624fb2b11bd177eb19fbb9ef9c341dc2b52f278",
    updated_at: "2026-08-13T08:48:58Z",
    assets: [
      {
        name: "Quill-Cowork-macOS-universal.dmg",
        state: "uploaded",
        browser_download_url: installerURL,
        digest: `sha256:${"a".repeat(64)}`,
        size: 29_252_809,
      },
    ],
    ...overrides,
  };
}

async function runSiteScript({ release, rejection } = {}) {
  const links = Array.from({ length: 3 }, () => ({ href: installerURL }));
  const labels = Array.from({ length: 2 }, () => ({
    textContent: "Latest tester release",
  }));
  const fetches = [];
  const document = {
    documentElement: { dataset: {} },
    querySelectorAll(selector) {
      if (selector === "[data-download-link]") {
        return links;
      }
      if (selector === "[data-build-label]") {
        return labels;
      }
      throw new Error(`Unexpected selector: ${selector}`);
    },
  };
  const fetch = async (url, options) => {
    fetches.push({ url, options });
    if (rejection) {
      throw rejection;
    }
    return { ok: true, json: async () => release };
  };

  vm.runInNewContext(source, { document, fetch }, { filename: "site.js" });
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
  return { document, fetches, labels, links };
}

const current = await runSiteScript({ release: releaseFixture() });
assert.equal(current.fetches.length, 1);
assert.equal(current.fetches[0].url, releaseAPIURL);
assert.equal(current.fetches[0].options.cache, "no-store");
assert.equal(
  current.fetches[0].options.headers.Accept,
  "application/vnd.github+json",
);
assert.equal(current.document.documentElement.dataset.release, "current");
assert.ok(current.labels.every((label) => label.textContent.startsWith("Updated ")));
assert.ok(current.links.every((link) => link.href === installerURL));

const malformed = releaseFixture({
  assets: [{
    ...releaseFixture().assets[0],
    digest: "sha256:not-a-digest",
  }],
});
const rejectedRelease = await runSiteScript({ release: malformed });
assert.equal(rejectedRelease.document.documentElement.dataset.release, undefined);
assert.ok(
  rejectedRelease.labels.every(
    (label) => label.textContent === "Latest tester release",
  ),
);

const unavailable = await runSiteScript({ rejection: new Error("offline") });
assert.equal(unavailable.document.documentElement.dataset.release, undefined);
assert.ok(
  unavailable.labels.every(
    (label) => label.textContent === "Latest tester release",
  ),
);

console.log("Verified Quill Cowork website release enhancement");
