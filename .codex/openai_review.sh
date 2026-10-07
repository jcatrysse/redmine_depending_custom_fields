#!/usr/bin/env bash
#
# Independent code review by an OpenAI model, as a second pair of eyes next to
# your own review. Runs only when OPENAI_API_KEY is set; without it, it prints
# SKIP and exits 0, and the report says the review was skipped.
#
#   ./.codex/openai_review.sh            # review <base>..HEAD
#   ./.codex/openai_review.sh <base>     # any commit, branch or tag
#
# Default base: the commit that added docs/REDMINE7-MIGRATION.md, so all work
# done after the plan; without that file, the merge base with the default
# branch.
#
# What is sent: the diff of this repository (plugin code, tests, locales,
# docs; screenshots, earlier reviews and the .codex tooling left out), CLAUDE.md and the work list
# of the migration plan. Never databases, logs, screenshots or credentials:
# the script refuses to send a diff that looks like it contains a secret.
#
# Output: docs/reviews/openai-<date>-<head>.md. Every finding gets a
# "Resolution:" line from you there (fixed in <commit>, or why not).
#
# Environment:
#   OPENAI_API_KEY        required to run
#   OPENAI_REVIEW_MODEL   default: $OPENAI_MODEL, else gpt-5
#   OPENAI_BASE_URL       default https://api.openai.com/v1
#   RMP_REVIEW_MAX_CHARS  diff characters per request (default 120000)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "SKIP: OPENAI_API_KEY is not set, no OpenAI review. Say so in the report."
  exit 0
fi

base="${1:-}"
if [ -z "$base" ]; then
  base="$(git log --diff-filter=A --format=%H -1 -- docs/REDMINE7-MIGRATION.md || true)"
fi
if [ -z "$base" ]; then
  default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/master)"
  base="$(git merge-base HEAD "$default")"
fi
git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "ERROR: unknown base '$base'" >&2; exit 2; }

mkdir -p docs/reviews
out="docs/reviews/openai-$(date +%Y-%m-%d)-$(git rev-parse --short HEAD).md"

python3 - "$base" "$out" <<'PY'
import json, os, re, subprocess, sys, urllib.error, urllib.request

base, out = sys.argv[1], sys.argv[2]
head = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], text=True).strip()
diff = subprocess.check_output(
    ['git', 'diff', '--no-color', '-M', f'{base}..HEAD', '--', '.',
     ':(exclude)docs/e2e/**', ':(exclude)docs/reviews/**', ':(exclude).codex/**',
     ':(exclude)*.png', ':(exclude)*.jpg',
     ':(exclude)Gemfile.lock', ':(exclude)vendor/**', ':(exclude)node_modules/**'],
    text=True, errors='replace')
if not diff.strip():
    print(f'Nothing to review: no changes between {base[:10]} and HEAD.')
    sys.exit(0)

secrets = re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----|\bsk-[A-Za-z0-9_-]{20,}|\bAKIA[0-9A-Z]{16}\b|'
                     r'\bgh[pousr]_[A-Za-z0-9]{30,}|\bxox[abprs]-[A-Za-z0-9-]{10,}')
hits = [l[:80] for l in diff.splitlines() if l.startswith('+') and secrets.search(l)]
if hits:
    print('REFUSED: the diff looks like it contains a secret; nothing was sent:', *hits, sep='\n  ')
    sys.exit(2)

def read(p, limit):
    return open(p, encoding='utf-8', errors='replace').read()[:limit] if os.path.exists(p) else ''

rules = read('CLAUDE.md', 20000)
plan = read('docs/REDMINE7-MIGRATION.md', 200000)
work = plan.split('## Work list for the migration session', 1)[-1].split('## How to test', 1)[0][:30000] if plan else ''

files = re.split(r'(?m)^(?=diff --git )', diff)
limit = int(os.environ.get('RMP_REVIEW_MAX_CHARS', '120000'))
chunks, cur = [], ''
for f in files:
    if len(f) > limit:
        f = f[:limit] + '\n[... this file\'s diff is cut here: too long for one request ...]\n'
    if cur and len(cur) + len(f) > limit:
        chunks.append(cur); cur = ''
    cur += f
if cur:
    chunks.append(cur)

model = os.environ.get('OPENAI_REVIEW_MODEL') or os.environ.get('OPENAI_MODEL') or 'gpt-5'
url = os.environ.get('OPENAI_BASE_URL', 'https://api.openai.com/v1').rstrip('/') + '/chat/completions'
system = (
    'You are a senior Redmine and Ruby on Rails reviewer doing an independent, adversarial code review of a '
    'Redmine plugin change. Target: Redmine 7.0 (Rails 8.1, Ruby 3.3+, Propshaft, Stimulus), and it must also '
    'run on PostgreSQL and MySQL/MariaDB. Look for real defects only: wrong behaviour, nil and edge cases, '
    'authorization gaps (every action and entry point, project and issue visibility), mass assignment, SQL '
    'built from params, XSS (html_safe/raw on user input), secrets in logs, N+1 queries or per-row work in '
    'views, non-portable SQL, irreversible migrations, Redmine 7 breakers (unloadable, removed helpers, '
    'icon CSS, ContextMenusController), webhook payloads that bypass what the plugin hides, locale keys '
    'missing in one shipped locale, tests that cannot fail or reimplement the code under test. '
    'Do not praise, do not summarise the change, no style nits unless they hide a bug. '
    'For each finding: severity (blocker, major, minor), file:line, the problem, a concrete failure scenario, '
    'and the fix. If you find nothing in this part, answer exactly "No findings." Answer in English.')

def ask(text, part, total):
    user = (f'Repository rules (CLAUDE.md):\n{rules}\n\nMigration work list (context):\n{work}\n\n'
            f'Diff part {part} of {total} ({base[:10]}..{head}):\n{text}')
    body = json.dumps({'model': model, 'messages': [{'role': 'system', 'content': system},
                                                   {'role': 'user', 'content': user}]}).encode()
    req = urllib.request.Request(url, data=body, headers={
        'Authorization': 'Bearer ' + os.environ['OPENAI_API_KEY'], 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors='replace')[:500]
        sys.exit(f'ERROR: OpenAI answered HTTP {e.code}: {detail}')
    except urllib.error.URLError as e:
        sys.exit(f'ERROR: cannot reach {url}: {e.reason} (network policy of this environment?)')
    return data['choices'][0]['message']['content'].strip(), data.get('usage', {})

parts, tokens = [], 0
for i, c in enumerate(chunks, 1):
    print(f'Sending part {i}/{len(chunks)} ({len(c)} characters) to {model} ...', flush=True)
    answer, usage = ask(c, i, len(chunks))
    tokens += usage.get('total_tokens', 0)
    parts.append(f'## Part {i} of {len(chunks)}\n\n{answer}\n')

n_files = len([f for f in files if f.strip()])
doc = (f'# OpenAI review {head}\n\nModel `{model}`, range `{base[:10]}..{head}`, {n_files} file(s), '
       f'{len(chunks)} request(s), {tokens} tokens.\n\n'
       'Add a `Resolution:` line under every finding: fixed in <commit>, or why not.\n\n' + '\n'.join(parts))
open(out, 'w').write(doc)
print(doc)
print(f'Written: {out}')
PY
