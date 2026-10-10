import fs from 'node:fs';
import path from 'node:path';

// Static inventory only. This script never connects to Supabase or prints keys.
const root = process.cwd();
const excluded = new Set(['.git', 'node_modules', 'dist', 'build']);
const extensions = new Set(['.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.html']);
const inventory = [];
function visit(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (excluded.has(entry.name) || entry.isSymbolicLink()) continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) { visit(absolute); continue; }
    if (!extensions.has(path.extname(entry.name))) continue;
    const text = fs.readFileSync(absolute, 'utf8');
    const collect = pattern => [...new Set([...text.matchAll(pattern)].map(match => match[1]))].sort();
    const hosts = collect(/https:\/\/([a-z]{20}\.supabase\.co)\b/g);
    const tables = collect(/\.from\(\s*['"`]([a-zA-Z_][a-zA-Z0-9_]*)['"`]\s*\)/g);
    const rpcs = collect(/\.rpc\(\s*['"`]([a-zA-Z_][a-zA-Z0-9_]*)['"`]/g);
    const schemas = collect(/\.schema\(\s*['"`]([a-zA-Z_][a-zA-Z0-9_]*)['"`]\s*\)/g);
    const functions = collect(/\/functions\/v1\/([a-zA-Z0-9_-]+)/g);
    if (hosts.length || tables.length || rpcs.length || schemas.length || functions.length) {
      inventory.push({ file: path.relative(root, absolute).split(path.sep).join('/'), hosts, tables, rpcs, schemas, functions });
    }
  }
}
visit(root);
inventory.sort((a, b) => a.file.localeCompare(b.file));
const report = {
  scope: 'Static literal references only; dynamic references and backend dependencies require separate review.',
  sourceProject: 'fumwwhyozeouoqscolke',
  destinationProject: 'jdxslqmgjsuzoisuhvlc',
  stagedSchema: 'tj',
  files: inventory,
};
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
