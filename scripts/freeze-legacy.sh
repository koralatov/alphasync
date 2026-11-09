#!/bin/bash
# Run once with an authenticated repository owner after the release checks pass.
set -euo pipefail
repository=koralatov/alphasync
branch=legacy-macos-11-12
tag=v1.5.1
source_repository=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# != 1 || ! "$1" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Usage: %s verified-release-commit\n' "$0" >&2
    exit 1
fi
release_commit=$1
test "$(gh api "repos/$repository/branches/$branch" --jq .commit.sha)" = "$release_commit"
test "$(gh api "repos/$repository/commits/$tag" --jq .sha)" = "$release_commit"
test "$(gh api "repos/$repository" --jq .permissions.admin)" = true

temporary=$(mktemp -d "${TMPDIR:-/tmp}/alphasync-freeze.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
gh release download "$tag" --repo "$repository" --dir "$temporary/downloads"
python3 "$source_repository/scripts/collect-release.py" --universal "$temporary/downloads" \
    --output "$temporary/verified" --tag "$tag" --source-commit "$release_commit"

# Lock only this branch, including administrators. The owner can still manage master.
gh api "repos/$repository/branches/$branch/protection" --method PUT --input - > /dev/null <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "lock_branch": true,
  "allow_fork_syncing": false
}
JSON
gh api "repos/$repository/branches/$branch/protection" > "$temporary/protection.json"
python3 - "$temporary/protection.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
assert p['lock_branch']['enabled'] and p['enforce_admins']['enabled']
assert not p['allow_force_pushes']['enabled'] and not p['allow_deletions']['enabled']
assert not p['allow_fork_syncing']['enabled']
PY

# Preserve the tag even if someone later removes the release record.
rule_id=$(gh api "repos/$repository/rulesets" --jq '.[] | select(.name == "Freeze v1.5.1") | .id')
if [[ -z "$rule_id" ]]; then
    rule_id=$(gh api "repos/$repository/rulesets" --method POST --input - --jq .id <<'JSON'
{
  "name": "Freeze v1.5.1",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["refs/tags/v1.5.1"], "exclude": []}},
  "rules": [{"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}]
}
JSON
)
fi
gh api "repos/$repository/rulesets/$rule_id" > "$temporary/tag-rule.json"
python3 - "$temporary/tag-rule.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r['target'] == 'tag' and r['enforcement'] == 'active' and not r['bypass_actors']
assert r['conditions']['ref_name'] == {'include': ['refs/tags/v1.5.1'], 'exclude': []}
assert {'update', 'deletion', 'non_fast_forward'} <= {x['type'] for x in r['rules']}
PY

# Immutability applies when a draft is published, not to an already published release.
gh api "repos/$repository/immutable-releases" --method PUT
test "$(gh api "repos/$repository/immutable-releases" --jq .enabled)" = true
test "$(gh api "repos/$repository/branches/$branch" --jq .commit.sha)" = "$release_commit"
test "$(gh api "repos/$repository/commits/$tag" --jq .sha)" = "$release_commit"
gh release edit "$tag" --repo "$repository" --draft=false --prerelease=false --latest
gh api "repos/$repository/releases/tags/$tag" > "$temporary/release.json"
python3 - "$temporary/release.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert not r['draft'] and not r['prerelease'] and r['immutable']
assert len(r['assets']) == 6
print('Published immutable AlphaSync 1.5.1 and verified the locked legacy branch and protected tag.')
print(r['html_url'])
PY
