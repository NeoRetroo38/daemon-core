// Runs locally with DATABASE_URL in the child environment, never as an argument or log field.
import { createRequire } from 'node:module';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
export function isAdditive(sql) {
  // Deliberately conservative: unsupported SQL requires operator review, not a guess.
  const clean = sql.replace(/--[^\n]*/g, '').trim();
  if (/\/\*|\$\$|\b(DROP|TRUNCATE|INSERT|SELECT|UPDATE\s+(?!CASCADE\b|RESTRICT\b|SET\b|NO\b)|DELETE\s+FROM|MERGE|COPY|DO|EXECUTE|FUNCTION|PROCEDURE|TRIGGER|GRANT|REVOKE|CHECK|INHERITS|GENERATED)\b/i.test(clean)) return false;
  if (/DEFAULT\s+(?!CURRENT_TIMESTAMP\b|true\b|false\b|null\b|[-+]?\d|')/i.test(clean)) return false;
  const statements = clean.split(';').map(s => s.trim()).filter(Boolean);
  return statements.length > 0 && statements.every(s =>
    /^CREATE\s+(?:TABLE|TYPE|(?:UNIQUE\s+)?INDEX)\s+"[a-zA-Z_][a-zA-Z0-9_]*"\s*[\s(]/i.test(s) ||
    /^ALTER\s+TABLE\s+"[a-zA-Z_][a-zA-Z0-9_]*"\s+ADD\s+(?:COLUMN|CONSTRAINT)\b/i.test(s)) &&
    !/\bALTER\s+COLUMN\b|,\s*(?:DROP|ALTER|RENAME)\b|\bRENAME\b/i.test(clean);
}
const fingerprint = path => createHash('sha256').update(readFileSync(path, 'utf8').replace(/\r\n/g, '\n')).digest('hex');
let stage = 'load-client';
async function main(release, mode) {
  const require = createRequire(join(release, 'apps/api/package.json'));
  const { PrismaClient } = require('@prisma/client');
  const db = new PrismaClient({ datasourceUrl: process.env.DATABASE_URL });
  try {
    const migrations = join(release, 'apps/api/prisma/migrations');
    stage = 'migration-status';
    const applied = await db.$queryRawUnsafe('SELECT migration_name, finished_at, rolled_back_at FROM "_prisma_migrations"');
    if (applied.some(row => !row.finished_at && !row.rolled_back_at)) throw new Error('Unfinished migration');
    const done = new Set(applied.filter(row => row.finished_at && !row.rolled_back_at).map(row => row.migration_name));
    const pending = readdirSync(migrations, { withFileTypes: true }).filter(d => d.isDirectory() && !done.has(d.name));
    stage = 'additive-sql';
    for (const dir of pending) if (!isAdditive(readFileSync(join(migrations, dir.name, 'migration.sql'), 'utf8'))) throw new Error('Non-additive or unsupported migration');
    if (mode === 'verify') {
      if (pending.length || !await db.permission.findUnique({ where: { key: 'cubes.manage.own' } })) throw new Error('Migration or permission missing');
      console.log('DATABASE_VERIFIED');
      return;
    }
    // The reviewed seed deletes stale catalogue rows. Refuse changes to its implementation
    // and refuse to run when either deleteMany would affect a row.
    stage = 'seed-fingerprint';
    if (fingerprint(join(release, 'apps/api/src/services/permissionsSeed.ts')) !== 'e4637014604f284a6da2d009fc5f652fabe70039febec4c4273c6731a762f54a' ||
        fingerprint(join(release, 'apps/api/src/seedCli.ts')) !== 'e98e98d53abbd22b77dd864694f99ccb4a104aa5abb2d9aa8e8c73ad19e32c57') throw new Error('Seed implementation needs review');
    stage = 'seed-removals';
    const { permissions, roleGrants } = await import(pathToFileURL(join(release, 'apps/api/dist/permissions.js')).href);
    let removals = await db.permission.count({ where: { key: { notIn: Object.keys(permissions) } } });
    for (const [role, granted] of Object.entries(roleGrants)) {
      removals += await db.rolePermission.count({ where: { role, permission: { key: { notIn: granted } } } });
    }
    if (removals !== 0) throw new Error('Seed would remove rows');
    console.log(`DATABASE_PREFLIGHT_OK pending=${pending.length} seedRemovals=0`);
  } finally { await db.$disconnect(); }
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main(resolve(process.argv[2]), process.argv[3]).catch(error => { console.error(`DATABASE_GUARD_FAILED stage=${stage} code=${/^P\d{4}$/.test(error?.code) ? error.code : 'CHECK'}`); process.exitCode = 1; });
}
