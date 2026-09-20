import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BASE_URL = process.env.VRT_BASE_URL || 'http://127.0.0.1:8888';

function loadPaths() {
  const configPath = path.join(__dirname, '..', '..', 'scan-urls.json');
  const raw = readFileSync(configPath, 'utf8');
  const paths = JSON.parse(raw);
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(`${configPath} must contain a non-empty JSON array of paths`);
  }
  return paths;
}

function snapshotName(urlPath) {
  if (urlPath === '/') {
    return 'front-page.png';
  }
  return `${urlPath.replace(/^\/+/, '').replace(/\/+/g, '-')}.png`;
}

for (const urlPath of loadPaths()) {
  test(`visual regression: ${urlPath}`, async ({ page }) => {
    await page.goto(new URL(urlPath, BASE_URL).toString(), { waitUntil: 'load' });
    await expect(page).toHaveScreenshot(snapshotName(urlPath), {
      fullPage: true,
      animations: 'disabled',
      maxDiffPixelRatio: 0.01,
    });
  });
}
