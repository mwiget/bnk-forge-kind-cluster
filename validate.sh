#!/usr/bin/env bash
# bnk-forge-kind-cluster — local validation script
#
# Mirrors the `make pre-push` shape from bnk-forge, sized for a content repo:
#
#   1. JSON-parse every bnkforge.pack.json + forge-blueprint.json
#   2. Cross-checks: every blueprint module reference points at a real module,
#      every ${...} variable reference resolves, every required module input
#      is wired by the blueprints
#   3. tofu fmt -check on every module (skipped if tofu missing)
#   4. tofu validate on every module (skipped if tofu missing — needs init)
#
# Exits non-zero on the first failure. Run before pushing changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
step()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
note()  { printf '  \033[33m·\033[0m %s\n' "$*"; }

ERRORS=0

# ---------------------------------------------------------------------------
# 1. JSON sanity
# ---------------------------------------------------------------------------
step "1/4  JSON sanity"

if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found — install jq to run validate.sh"
  exit 1
fi

while IFS= read -r f; do
  if jq -e . "$f" >/dev/null 2>&1; then
    ok "$f"
  else
    fail "$f does not parse as JSON"
    ERRORS=$((ERRORS + 1))
  fi
done < <(find modules blueprints -name 'bnkforge.pack.json' -o -name 'forge-blueprint.json' | sort)

# ---------------------------------------------------------------------------
# 2. Cross-checks (blueprint ↔ module wiring)
# ---------------------------------------------------------------------------
step "2/4  Blueprint ↔ module wiring"

if ! command -v node >/dev/null 2>&1; then
  fail "node not found — install Node.js to run cross-checks"
  exit 1
fi

# Embedded JS validator. Reads each forge-blueprint.json and:
#  - confirms every module reference points at a real modules/<path>/bnkforge.pack.json
#  - confirms every ${...} reference resolves to a declared blueprint input or to
#    a previously-declared module's outputs
#  - confirms every input declared `required` on a module is supplied by the blueprint
node - <<'EOF' || ERRORS=$((ERRORS + 1))
const fs = require('fs');
const path = require('path');

const blueprints = fs.readdirSync('blueprints')
  .map(d => path.join('blueprints', d, 'forge-blueprint.json'))
  .filter(p => fs.existsSync(p));

let bad = 0;
const ok   = (s) => console.log('  \x1b[32m✓\x1b[0m ' + s);
const fail = (s) => { console.error('  \x1b[31m✗\x1b[0m ' + s); bad++; };

function resolveRef(manifest, ref) {
  if (ref.startsWith('modules.')) {
    const parts = ref.split('.');
    if (parts.length < 4 || parts[2] !== 'outputs') return 'malformed reference';
    const moduleId = parts[1];
    if (!manifest.modules.find(m => m.id === moduleId)) return 'unknown module id ' + moduleId;
    return null;
  }
  const declared = new Set();
  for (const set of Object.values(manifest.inputs || {})) for (const i of set) declared.add(i.name);
  return declared.has(ref) ? null : 'undeclared blueprint input ' + ref;
}

for (const bp of blueprints) {
  const manifest = JSON.parse(fs.readFileSync(bp, 'utf8'));
  console.log('\n  ' + bp);

  for (const mod of manifest.modules) {
    // 1. Module path exists
    const packPath = path.join(mod.module, 'bnkforge.pack.json');
    if (!fs.existsSync(packPath)) {
      fail(`${mod.id} -> ${mod.module}: module not found`);
      continue;
    }

    const pack = JSON.parse(fs.readFileSync(packPath, 'utf8'));

    // 2. ${...} references resolve
    const issues = [];
    for (const [k, v] of Object.entries(mod.inputs || {})) {
      if (typeof v !== 'string' || !v.startsWith('${') || !v.endsWith('}')) continue;
      const err = resolveRef(manifest, v.slice(2, -1));
      if (err) issues.push(`${k}: ${err}`);
    }

    // 3. Required module inputs are wired
    const required = (pack.inputs.required || []).map(i => i.name);
    const supplied = new Set(Object.keys(mod.inputs || {}));
    const missing  = required.filter(n => !supplied.has(n));
    if (missing.length) issues.push('missing required: ' + missing.join(', '));

    if (issues.length) fail(`${mod.id}: ` + issues.join('; '));
    else ok(`${mod.id}`);
  }
}

if (bad) {
  console.error(`\n  \x1b[31m${bad}\x1b[0m wiring issue(s)`);
  process.exit(1);
}
EOF

# ---------------------------------------------------------------------------
# 3. tofu fmt -check
# ---------------------------------------------------------------------------
step "3/4  tofu fmt -check"

if ! command -v tofu >/dev/null 2>&1; then
  note "tofu not found — skipping format check"
else
  while IFS= read -r d; do
    if tofu fmt -check -recursive "$d" >/dev/null 2>&1; then
      ok "$d"
    else
      fail "$d not formatted (run \`tofu fmt -recursive $d\`)"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(find modules -mindepth 1 -maxdepth 1 -type d | sort)
fi

# ---------------------------------------------------------------------------
# 4. tofu validate (needs init — opt-in via VALIDATE=1)
# ---------------------------------------------------------------------------
step "4/4  tofu validate"

if ! command -v tofu >/dev/null 2>&1; then
  note "tofu not found — skipping"
elif [ "${VALIDATE:-0}" != "1" ]; then
  note "skipped — set VALIDATE=1 to run \`tofu init && tofu validate\` per module (slow, network)"
else
  while IFS= read -r d; do
    pushd "$d" >/dev/null
    if tofu init -backend=false -input=false -no-color >/tmp/tofu-init.log 2>&1 && \
       tofu validate -no-color >/tmp/tofu-validate.log 2>&1; then
      ok "$d"
    else
      fail "$d"
      sed -n '1,30p' /tmp/tofu-validate.log >&2 || true
      ERRORS=$((ERRORS + 1))
    fi
    rm -rf .terraform .terraform.lock.hcl
    popd >/dev/null
  done < <(find modules -mindepth 1 -maxdepth 1 -type d | sort)
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [ "$ERRORS" -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%d check(s) failed.\033[0m\n' "$ERRORS"
  exit 1
fi
