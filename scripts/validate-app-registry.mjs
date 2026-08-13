import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const registryPath = resolve('config/app-registry.json');
const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
const deployable = [registry.platform, ...(registry.apps || [])].filter(Boolean);
const all = [...deployable, ...(registry.legacy || [])];
const errors = [];
const warnings = [];

const keys = new Set();
const siteIds = new Map();
const urls = new Map();

for (const app of all) {
  if (!app.key) errors.push('Registry entry missing key');
  if (keys.has(app.key)) errors.push(`Duplicate app key: ${app.key}`);
  keys.add(app.key);

  if (app.netlify_site_id) {
    if (siteIds.has(app.netlify_site_id)) errors.push(`Duplicate Netlify site id: ${app.netlify_site_id} (${app.key}, ${siteIds.get(app.netlify_site_id)})`);
    siteIds.set(app.netlify_site_id, app.key);
  }
  if (app.production_url) {
    if (urls.has(app.production_url)) errors.push(`Duplicate production URL: ${app.production_url}`);
    urls.set(app.production_url, app.key);
    if (!app.production_url.startsWith('https://')) errors.push(`${app.key}: production_url must use https`);
  }

  if (app.deploy_on_main) {
    if (!app.source_path) errors.push(`${app.key}: deploy_on_main requires source_path`);
    if (!app.netlify_site_id) errors.push(`${app.key}: deploy_on_main requires netlify_site_id`);
    if (!app.production_url) errors.push(`${app.key}: deploy_on_main requires production_url`);
  }

  if (app.source_path) {
    if (!existsSync(app.source_path)) errors.push(`${app.key}: source path does not exist: ${app.source_path}`);
    else if (!existsSync(resolve(app.source_path, 'index.html'))) warnings.push(`${app.key}: no index.html at ${app.source_path}/index.html`);
  }
}

for (const entry of registry.legacy || []) {
  if (!entry.replacement) warnings.push(`${entry.key}: legacy entry has no replacement`);
}

if (warnings.length) {
  console.log('\nRegistry warnings:');
  for (const warning of warnings) console.log(`- ${warning}`);
}

if (errors.length) {
  console.error('\nRegistry validation failed:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

const matrix = deployable
  .filter(app => app.deploy_on_main)
  .map(app => ({
    key: app.key,
    name: app.name,
    source_path: app.source_path,
    site_id: app.netlify_site_id,
    production_url: app.production_url,
    smoke_path: app.smoke_path || '/'
  }));

console.log(`Validated ${all.length} registry entries; ${matrix.length} deployable on main.`);
if (process.argv.includes('--matrix')) process.stdout.write(`\n${JSON.stringify({ include: matrix })}\n`);
