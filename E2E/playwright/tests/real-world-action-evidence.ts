import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { type TestType } from '@playwright/test';

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
  },
  {
    name: 'recovers transient runtime failures with the same actionable turn',
    prompts: ['trigger network failure', 'Retry runtime issue'],
    expectedToolNames: ['host.shell.run'],
    regressionGuards: [
      'runtime issue retry clears the transient failure',
      'retry dispatches a concrete nonempty shell action',
      'retry preserves the user turn instead of creating draft-only limbo'
    ]
  }
];

export function registerRealWorldActionEvidenceManifest(test: Pick<TestType<{}, {}>, 'afterAll'>) {
  test.afterAll(() => {
    const artifactDir = process.env.QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR;
    if (!artifactDir) {
      return;
    }

    mkdirSync(artifactDir, { recursive: true });
    writeFileSync(
      join(artifactDir, 'playwright-real-world-actions-manifest.json'),
      `${JSON.stringify(realWorldActionEvidenceManifest(), null, 2)}\n`,
      'utf8'
    );
  });
}

function realWorldActionEvidenceManifest() {
  return {
    generatedAt: new Date().toISOString(),
    suite: 'playwright-real-world-actions',
    scenarioCount: evidenceScenarios.length,
    promptCount: sumEvidenceCounts('prompts'),
    regressionGuardCount: sumEvidenceCounts('regressionGuards'),
    scenarios: evidenceScenarios
  };
}

function sumEvidenceCounts(field: 'prompts' | 'regressionGuards') {
  return evidenceScenarios.reduce((count, scenario) => count + scenario[field].length, 0);
}
