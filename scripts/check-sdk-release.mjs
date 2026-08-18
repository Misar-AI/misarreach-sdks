#!/usr/bin/env node
/**
 * Release-readiness gate for the SDK fleet.
 *
 *   node scripts/check-sdk-release.mjs <sdk> <version>
 *   node scripts/check-sdk-release.mjs --all          (metadata only)
 *
 * Every registry in this fleet treats a published version as PERMANENT. npm's
 * unpublish window is 72 hours, crates.io and the Go module proxy are immutable
 * outright, and Maven Central has no delete at all. So the expensive failure is
 * not "the publish job errored" — it is "the publish job succeeded with the
 * wrong contents", because that cannot be taken back.
 *
 * This runs BEFORE any credential is touched. It answers one question per SDK:
 * would publishing this tree, at this version, be a mistake we cannot undo?
 *
 * The tag is the authority on version. A tag that disagrees with the manifest
 * is always an error rather than something to reconcile — silently trusting
 * either one is how `sdk-python-v1.0.2` ends up publishing 1.0.1 forever.
 */

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

// Two layouts, one script. In this monorepo the SDKs live under sdks/; in the
// public mirror they ARE the repository root (typescript/, python/, …). The
// mirror runs this same file, so it must work in both rather than growing a
// second copy that drifts.
const SDKS = existsSync(join(ROOT, "sdks", "typescript")) ? join(ROOT, "sdks") : ROOT;

/**
 * How to read the shipped version out of each language's manifest.
 *
 * PHP is deliberately absent a version: Packagist derives versions from git
 * tags, and a `version` field in composer.json fights that. Its entry asserts
 * the field stays absent.
 */
const MANIFESTS = {
  typescript: { file: "typescript/package.json", read: (s) => JSON.parse(s).version, registry: "npm" },
  python:     { file: "python/pyproject.toml", read: (s) => match(s, /^version\s*=\s*"([^"]+)"/m), registry: "PyPI" },
  rust:       { file: "rust/Cargo.toml", read: (s) => match(s, /^version\s*=\s*"([^"]+)"/m), registry: "crates.io" },
  ruby:       { file: "ruby/misar_reach.gemspec", read: (s) => match(s, /version\s*=\s*"([^"]+)"/), registry: "RubyGems" },
  dart:       { file: "dart/pubspec.yaml", read: (s) => match(s, /^version:\s*(\S+)/m), registry: "pub.dev" },
  flutter:    { file: "flutter/pubspec.yaml", read: (s) => match(s, /^version:\s*(\S+)/m), registry: "pub.dev" },
  java:       { file: "java/pom.xml", read: (s) => match(s, /<version>([^<]+)<\/version>/), registry: "Maven Central" },
  kotlin:     { file: "kotlin/build.gradle.kts", read: (s) => match(s, /^version\s*=\s*"([^"]+)"/m), registry: "Maven Central" },
  csharp:     { file: "csharp/MisarReach.csproj", read: (s) => match(s, /<Version>([^<]+)<\/Version>/), registry: "NuGet" },
  go:         { file: "go/go.mod", read: () => null, registry: "Go proxy (tag-versioned)" },
  swift:      { file: "swift/Package.swift", read: () => null, registry: "Swift PM (tag-versioned)" },
  php:        { file: "php/composer.json", read: () => null, registry: "Packagist (tag-versioned)" },
};

function match(s, re) {
  const m = s.match(re);
  return m ? m[1] : null;
}

/**
 * Cheap structural checks per format. Node has no TOML or YAML parser in core
 * and this repo should not grow a dependency for a release gate, so these check
 * the one failure that blind text edits actually cause: a duplicated key.
 * Returns a problem string, or null when the file looks well-formed.
 */
function validateStructure(file, text) {
  if (file.endsWith(".json")) {
    try {
      JSON.parse(text);
    } catch (err) {
      return `${file} is not valid JSON: ${err.message}`;
    }
    return null;
  }

  if (file.endsWith(".toml")) {
    // Duplicate keys within one [table] — invalid TOML, silently regex-readable.
    let table = "";
    const seen = new Map();
    for (const raw of text.split("\n")) {
      const line = raw.trim();
      if (line.startsWith("#") || !line) continue;
      const t = line.match(/^\[([^\]]+)\]$/);
      if (t) {
        table = t[1];
        continue;
      }
      const k = line.match(/^([A-Za-z0-9_.-]+)\s*=/);
      if (!k) continue;
      const key = `${table}.${k[1]}`;
      if (seen.has(key)) return `${file} defines "${k[1]}" twice in [${table}] — invalid TOML`;
      seen.set(key, true);
    }
    return null;
  }

  if (file.endsWith(".yaml") || file.endsWith(".yml")) {
    const keys = text
      .split("\n")
      .map((l) => l.match(/^([a-z_]+):/i))
      .filter(Boolean)
      .map((m) => m[1]);
    const dupe = keys.find((k, i) => keys.indexOf(k) !== i);
    if (dupe) return `${file} defines top-level "${dupe}" twice`;
    return null;
  }

  return null;
}

const problems = [];
const notes = [];
const linkChecks = [];
const fail = (sdk, msg) => problems.push(`${sdk}: ${msg}`);

// Only a definitive "this is not there" blocks a release: 404/410, or a host that
// does not resolve. A timeout or a 5xx is the registry having a bad minute, not a
// broken link, and failing on those would make the gate refuse good releases.
async function verifyLinks(checks) {
  const byUrl = new Map();
  for (const { sdk, url } of checks) {
    if (!byUrl.has(url)) byUrl.set(url, new Set());
    byUrl.get(url).add(sdk);
  }
  await Promise.all([...byUrl].map(async ([url, sdks]) => {
    let verdict = null;
    try {
      const res = await fetch(url, {
        redirect: "follow",
        signal: AbortSignal.timeout(15000),
        headers: { "User-Agent": "misar-sdk-release-gate" },
      });
      if (res.status === 404 || res.status === 410) verdict = `returns ${res.status}`;
    } catch (err) {
      // fetch collapses DNS failure, TLS failure and timeout into one TypeError,
      // so pick out the one that means the host genuinely is not there.
      const cause = String(err?.cause?.code ?? "");
      if (cause === "ENOTFOUND" || cause === "EAI_AGAIN") verdict = "does not resolve";
    }
    if (verdict) for (const sdk of sdks) fail(sdk, `manifest links ${url}, which ${verdict}`);
  }));
}

function checkOne(sdk, wantVersion) {
  const spec = MANIFESTS[sdk];
  if (!spec) {
    fail(sdk, `unknown SDK. Known: ${Object.keys(MANIFESTS).sort().join(", ")}`);
    return;
  }

  const dir = join(SDKS, sdk);
  if (!existsSync(dir)) return fail(sdk, `sdks/${sdk}/ does not exist`);

  const manifestPath = join(SDKS, spec.file);
  if (!existsSync(manifestPath)) return fail(sdk, `missing manifest ${spec.file}`);

  // A package page with no licence is a package most companies cannot adopt,
  // and Maven Central rejects the release outright.
  if (!existsSync(join(dir, "LICENSE"))) fail(sdk, "no LICENSE file");
  if (!existsSync(join(dir, "README.md"))) fail(sdk, "no README.md — this is the package's entire landing page");

  const manifest = readFileSync(manifestPath, "utf8");

  // Parse-validate, don't just pattern-match. A regex happily reads a version
  // out of a manifest that no parser will accept — this gate passed a
  // pyproject.toml with a duplicate key, which would have failed at build time
  // instead of here.
  const structural = validateStructure(spec.file, manifest);
  if (structural) fail(sdk, structural);

  // Dead links render as a broken "Repository"/"Homepage" on the package page.
  // Checked for real rather than against a hand-maintained list of hosts believed
  // dead: that list still called docs.misar.io/reach a 404 long after the docs
  // site went live, and blocked a release over a URL that works.
  // An XML namespace is an identifier that happens to look like a URL; nothing is
  // expected to be served there and maven.apache.org/POM/4.0.0 genuinely 404s. Drop
  // those attributes before looking for links, or every pom.xml fails this check.
  const linkText = manifest.replace(/xmlns(?::\w+)?="[^"]*"/g, "")
                           .replace(/xsi:schemaLocation="[^"]*"/g, "");
  for (const url of linkText.match(/https?:\/\/[^\s"'<>)\]},\\]+/g) ?? []) {
    linkChecks.push({ sdk, url: url.replace(/[.,;:]+$/, "") });
  }

  const declared = spec.read(manifest);

  if (declared === null) {
    notes.push(`${sdk}: version comes from the git tag (${spec.registry}) — manifest carries none, which is correct`);
    return;
  }

  if (!wantVersion) {
    notes.push(`${sdk}: ${declared} → ${spec.registry}`);
    return;
  }

  if (declared !== wantVersion) {
    fail(
      sdk,
      `tag says ${wantVersion} but ${spec.file} says ${declared}. ` +
        `Bump the manifest and re-tag — publishing would ship ${declared} under the ${wantVersion} tag, permanently.`,
    );
  } else {
    notes.push(`${sdk}: ${declared} matches the tag → ${spec.registry}`);
  }
}

// ── Entry ────────────────────────────────────────────────────────────────────

const [arg1, arg2] = process.argv.slice(2);

if (!arg1 || arg1 === "--all") {
  for (const sdk of Object.keys(MANIFESTS).sort()) checkOne(sdk, null);
} else {
  if (arg2 && !/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(arg2)) {
    fail(arg1, `"${arg2}" is not a semver version`);
  }
  checkOne(arg1, arg2 ?? null);
}

await verifyLinks(linkChecks);

for (const n of notes) console.log(`  ok   ${n}`);
for (const p of problems) console.error(`  FAIL ${p}`);

if (problems.length) {
  console.error(`\n${problems.length} problem(s) — refusing to publish.`);
  process.exit(1);
}
console.log(`\nRelease readiness: OK`);
