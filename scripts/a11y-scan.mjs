#!/usr/bin/env node
import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WCAG_TAGS = ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'];

function parseArgs(argv) {
  let baseUrl = 'http://127.0.0.1:8888';
  for (const arg of argv) {
    if (arg.startsWith('--base-url=')) {
      baseUrl = arg.slice('--base-url='.length);
    }
  }
  return { baseUrl };
}

function loadUrls() {
  const configPath = path.join(__dirname, '..', 'scan-urls.json');
  const raw = readFileSync(configPath, 'utf8');
  const paths = JSON.parse(raw);
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(`${configPath} must contain a non-empty JSON array of paths`);
  }
  return paths;
}

function reportViolations(url, violations) {
  for (const violation of violations) {
    const sample = violation.nodes[0]?.target?.join(' ') ?? '(no selector)';
    console.log(
      `[VIOLATION] ${url} - ${violation.id} (${violation.impact}) ` +
      `tags=${violation.tags.join(',')} count=${violation.nodes.length} sample="${sample}"`
    );
  }
}

async function main() {
  const { baseUrl } = parseArgs(process.argv.slice(2));
  const paths = loadUrls();

  const browser = await chromium.launch();
  let totalViolations = 0;
  let loadFailures = 0;

  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    for (const urlPath of paths) {
      const url = new URL(urlPath, baseUrl).toString();
      const response = await page.goto(url, { waitUntil: 'load' });
      if (!response || response.status() >= 400) {
        const status = response ? response.status() : 'no response';
        console.error(`[LOAD FAILURE] ${url} - HTTP status ${status}`);
        loadFailures += 1;
        continue;
      }
      const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
      reportViolations(url, results.violations);
      totalViolations += results.violations.length;
    }
  } finally {
    await browser.close();
  }

  if (loadFailures > 0) {
    console.error(`\n${loadFailures} page(s) failed to load across ${paths.length} page(s).`);
    process.exitCode = 1;
  }

  if (totalViolations > 0) {
    console.error(`\n${totalViolations} accessibility violation(s) found across ${paths.length} page(s).`);
    process.exitCode = 1;
  } else if (loadFailures === 0) {
    console.log(`\nNo accessibility violations found across ${paths.length} page(s) (${WCAG_TAGS.join(', ')}).`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
