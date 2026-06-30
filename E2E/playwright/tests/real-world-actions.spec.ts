import { test, expect } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { harnessURL } from './harness-helpers';

type RealWorldEvidenceScenario = {
  name: string;
  prompts: string[];
  expectedToolNames: string[];
  regressionGuards: string[];
};

const evidenceScenarios: RealWorldEvidenceScenario[] = [
  {
    name: 'runs natural shell requests immediately with nonempty arguments',
    prompts: [
      'whoami?',
      'Run `ls`',
      'Please run `printf quillcode_now_smoke` now and report the output.',
      'Can you run printf quillcode_polite_smoke?',
      'Can you show me the current directory?'
    ],
    expectedToolNames: ['host.shell.run'],
    regressionGuards: [
      'shell arguments are never {}',
      'assistant does not answer with passive promises',
      'output is visible in the chat transcript'
    ]
  },
  {
    name: 'lists workspace entries with the structured file list tool',
    prompts: ['Can you list the files here?'],
    expectedToolNames: ['host.file.list'],
    regressionGuards: [
      'file list arguments stay workspace-relative',
      'file list uses host.file.list instead of shell ls fallback',
      'listed entries render as final chat text'
    ]
  },
  {
    name: 'writes requested file content immediately without a confirmation loop',
    prompts: ['Can you write a file that says "hello world"'],
    expectedToolNames: ['host.file.write'],
    regressionGuards: [
      'file write arguments include path and content',
      'artifact preview renders the written file',
      'assistant does not ask for a second confirmation'
    ]
  },
  {
    name: 'reads requested file contents immediately with the structured file tool',
    prompts: ['What is in README.md?'],
    expectedToolNames: ['host.file.read'],
    regressionGuards: [
      'file read arguments include a workspace-relative path',
      'file read uses host.file.read instead of shell cat fallback',
      'assistant does not answer with passive promises'
    ]
  },
  {
    name: 'searches workspace text with the structured file search tool',
    prompts: ['Where is AgentRunner defined?'],
    expectedToolNames: ['host.file.search'],
    regressionGuards: [
      'file search arguments include a nonempty query',
      'file search uses host.file.search instead of shell grep fallback',
      'search results render as final chat text'
    ]
  },
  {
    name: 'answers device diagnostic prompts with concrete shell actions',
    prompts: ['How much hd?', 'Do you have openclaw?'],
    expectedToolNames: ['host.shell.run'],
    regressionGuards: [
      'diagnostic shell arguments are never {}',
      'device answers are rendered as final chat text',
      'empty shell failures stay absent'
    ]
  },
  {
    name: 'downloads requested domains with a bounded concrete shell action',
    prompts: ['Can you download LinkedIn.com?'],
    expectedToolNames: ['host.shell.run'],
    regressionGuards: [
      'download command is bounded to a workspace-relative output path',
      'download command is concrete and nonempty',
      'safety review does not block clear user intent'
    ]
  },
  {
    name: 'answers natural git read requests with structured git tools',
    prompts: ['Please check git status.', 'what changed?'],
    expectedToolNames: ['host.git.status', 'host.git.diff'],
    regressionGuards: [
      'git status uses host.git.status instead of shell fallback',
      'natural diff wording uses host.git.diff',
      'git read outputs render as final chat text'
    ]
  },
  {
    name: 'dispatches slash git read shortcuts as real workspace actions',
    prompts: ['/git-status', '/diff'],
    expectedToolNames: ['host.git.status', 'host.git.diff'],
    regressionGuards: [
      'slash git status dispatches host.git.status',
      'slash diff dispatches host.git.diff',
      'slash quick actions render final chat text without draft-only limbo'
    ]
  },
  {
    name: 'starter cards launch real workspace actions immediately',
    prompts: ['Review changes starter card'],
    expectedToolNames: ['host.git.diff'],
    regressionGuards: [
      'starter card creates a user turn without draft-only limbo',
      'starter card dispatches the normal git diff tool',
      'composer is cleared after starter submission'
    ]
  },
  {
    name: 'respects explicit negative action prompts without tool cards or side effects',
    prompts: [
      'Do not run whoami.',
      'Do not write `forbidden.txt` with content `nope`.',
      "Don't download https://example.com into `downloads/forbidden.html`."
    ],
    expectedToolNames: [],
    regressionGuards: [
      'negative shell intent creates no tool card',
      'negative write intent creates no artifact',
      'negative download intent creates no artifact'
    ]
  }
];

test.afterAll(() => {
  const artifactDir = process.env.QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR;
  if (!artifactDir) {
    return;
  }

  mkdirSync(artifactDir, { recursive: true });
  writeFileSync(
    join(artifactDir, 'playwright-real-world-actions-manifest.json'),
    `${JSON.stringify({
      generatedAt: new Date().toISOString(),
      suite: 'playwright-real-world-actions',
      scenarioCount: evidenceScenarios.length,
      promptCount: evidenceScenarios.reduce((count, scenario) => count + scenario.prompts.length, 0),
      regressionGuardCount: evidenceScenarios.reduce(
        (count, scenario) => count + scenario.regressionGuards.length,
        0
      ),
      scenarios: evidenceScenarios
    }, null, 2)}\n`,
    'utf8'
  );
});

test('runs natural shell requests immediately with nonempty arguments', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('whoami?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"cmd": "whoami"');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('whoami?');
  await expect(page.getByTestId('tool-card-output')).toContainText('mock-user');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll run|I'?ll check|should I|do you want me to/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Run `ls`');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "ls"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('ran: ls');
  await expect(page.getByText('Output:\nran: ls')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Please run `printf quillcode_now_smoke` now and report the output.');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(3);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "printf quillcode_now_smoke"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('quillcode_now_smoke');
  await expect(page.getByText('Output:\nquillcode_now_smoke')).toBeVisible();
  await expect(page.getByText(/I'?ll run|I'?ll check|should I|do you want me to|ok\?/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Can you run printf quillcode_polite_smoke?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(4);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "printf quillcode_polite_smoke"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('quillcode_polite_smoke');
  await expect(page.getByText('Output:\nquillcode_polite_smoke')).toBeVisible();
  await expect(page.getByText(/I'?ll run|I'?ll check|should I|do you want me to|ok\?/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Can you show me the current directory?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(5);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "pwd"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('/mock/QuillCode');
  await expect(page.getByText('Output:\n/mock/QuillCode')).toBeVisible();
  await expect(page.getByText(/I'?ll show|should I|do you want me to|ok\?/i)).toHaveCount(0);
});

test('lists workspace entries with the structured file list tool', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you list the files here?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.list');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"path": "."');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('README.md');
  await expect(page.getByTestId('tool-card-output')).toContainText('Sources');
  await expect(page.getByText('`.` contains 2 entries:')).toBeVisible();
  await expect(page.getByText(/`Sources\/` · directory/)).toBeVisible();
  await expect(page.getByText(/`README\.md` · file/)).toBeVisible();
  await expect(page.getByText(/I'?ll list|should I|do you want me to|ok\?/i)).toHaveCount(0);
  await expect(page.getByText(/ran: ls -la|No shell command was specified/i)).toHaveCount(0);
});

test('writes requested file content immediately without a confirmation loop', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you write a file that says "hello world"');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('message')).toHaveCount(2);
  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"path": "hello.txt"');
  await expect(page.getByTestId('tool-card-input')).toContainText('hello world');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('hello.txt');
  await expect(page.getByTestId('tool-card-text-preview-content')).toHaveText('hello world');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode/hello.txt');
  await expect(page.getByText('Wrote `hello.txt`.')).toBeVisible();
  await expect(page.getByText(/I'?ll write|should I|do you want me to|ok\?/i)).toHaveCount(0);
});

test('reads requested file contents immediately with the structured file tool', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('What is in README.md?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.read');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"path": "README.md"');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('# QuillCode');
  await expect(page.getByText(/Contents of `README\.md`:\s*# QuillCode/)).toBeVisible();
  await expect(page.getByText(/No shell command was specified|I'?ll read|I will read|cat README/i)).toHaveCount(0);
});

test('searches workspace text with the structured file search tool', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Where is AgentRunner defined?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.search');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"query": "AgentRunner"');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('Sources/Agent.swift');
  await expect(page.getByText(/Found 1 match for `AgentRunner`:/)).toBeVisible();
  await expect(page.getByText(/`Sources\/Agent\.swift:1`: struct AgentRunner/)).toBeVisible();
  await expect(page.getByText(/No shell command was specified|grep AgentRunner|I'?ll search|I will search/i)).toHaveCount(0);
});

test('answers device diagnostic prompts with concrete shell actions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('How much hd?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"cmd": "df -h / /Quill 2>/dev/null || df -h /"');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode');
  await expect(page.getByText('Workspace storage: 15% used.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll check|should I|do you want me to/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Do you have openclaw?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input').last())
    .toContainText('"cmd": "command -v openclaw || which openclaw || echo \'not found\'"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('not found');
  await expect(page.getByText('OpenClaw is not installed.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll check|should I|do you want me to/i)).toHaveCount(0);
});

test('downloads requested domains with a bounded concrete shell action', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you download LinkedIn.com?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('curl -L --fail --silent --show-error');
  await expect(page.getByTestId('tool-card-input')).toContainText("--output 'downloads/linkedin.com.html'");
  await expect(page.getByTestId('tool-card-input')).toContainText('https://www.linkedin.com');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('downloads/linkedin.com.html');
  await expect(page.getByText('Downloaded to `downloads/linkedin.com.html`.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll download|should I|do you want me to|confirm user intent/i)).toHaveCount(0);
});

test('answers natural git read requests with structured git tools', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Please check git status.');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.status');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('Sources/App.swift');
  await expect(page.getByText(/Git status:\s*## main\s*M Sources\/App.swift/)).toBeVisible();
  await expect(page.getByText(/No shell command was specified|I'?ll check|should I|do you want me to/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('what changed?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('diff --git a/Sources/App.swift b/Sources/App.swift');
  await expect(page.getByText(/Git diff:\s*diff --git a\/Sources\/App.swift b\/Sources\/App.swift/)).toBeVisible();
  await expect(page.getByText(/No shell command was specified|I'?ll check|should I|do you want me to/i)).toHaveCount(0);
});

test('dispatches slash git read shortcuts as real workspace actions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/git-status');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.status');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('Sources/App.swift');
  await expect(page.getByText(/Git status:\s*## main\s*M Sources\/App.swift/)).toBeVisible();
  await expect(page.getByLabel('Message')).toHaveValue('');
  await expect(page.getByTestId('send-button')).toBeDisabled();
  await expect(page.getByText(/No shell command was specified|I'?ll check|should I|do you want me to|ok\?/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('/diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('diff --git a/Sources/App.swift b/Sources/App.swift');
  await expect(page.getByText(/Git diff:\s*diff --git a\/Sources\/App.swift b\/Sources\/App.swift/)).toBeVisible();
  await expect(page.getByLabel('Message')).toHaveValue('');
  await expect(page.getByTestId('send-button')).toBeDisabled();
  await expect(page.getByText(/No shell command was specified|I'?ll review|I will review|should I|do you want me to|ok\?/i)).toHaveCount(0);
});

test('starter cards launch real workspace actions immediately', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('transcript-empty')).toBeVisible();

  await page.getByTestId('empty-starter-action').filter({ hasText: 'Review changes' }).click();

  await expect(page.getByTestId('transcript-empty')).toHaveCount(0);
  await expect(page.getByTestId('message').filter({
    hasText: 'Review the current git diff and call out risks, missing tests, and next steps.'
  })).toBeVisible();
  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('diff --git a/Sources/App.swift b/Sources/App.swift');
  await expect(page.getByText(/Git diff:\s*diff --git a\/Sources\/App.swift b\/Sources\/App.swift/)).toBeVisible();
  await expect(page.getByLabel('Message')).toHaveValue('');
  await expect(page.getByTestId('send-button')).toBeDisabled();
  await expect(page.getByText(/I'?ll review|I will review|should I|do you want me to|ok\?/i)).toHaveCount(0);
});

test('respects explicit negative action prompts without tool cards or side effects', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Do not run whoami.');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('message')).toHaveCount(2);
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
  await expect(page.getByText("Okay, I won't take that action.")).toBeVisible();
  await expect(page.getByText(/You are `mock-user`|No shell command was specified/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Do not write `forbidden.txt` with content `nope`.');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('message')).toHaveCount(4);
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
  await expect(page.getByText("Okay, I won't take that action.")).toHaveCount(2);
  await expect(page.getByText('Wrote `forbidden.txt`.')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveCount(0);

  await page.getByLabel('Message').fill("Don't download https://example.com into `downloads/forbidden.html`.");
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('message')).toHaveCount(6);
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
  await expect(page.getByText("Okay, I won't take that action.")).toHaveCount(3);
  await expect(page.getByText('Downloaded to `downloads/forbidden.html`.')).toHaveCount(0);
  await expect(page.getByText(/I'?ll run|I'?ll write|I'?ll download|should I|do you want me to/i)).toHaveCount(0);
});
