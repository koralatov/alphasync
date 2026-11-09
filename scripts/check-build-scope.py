#!/usr/bin/env python3
"""Skip Mac builds only when a known comparison contains documentation alone."""
import json
import os
from pathlib import Path
import re
import subprocess


def requires_build(event, event_name, repository):
    if event_name == 'push':
        message = (event.get('head_commit') or {}).get('message', '')
        if message.split('\n', 1)[0].startswith('Release AlphaSync '):
            return True
        base, head = event.get('before'), event.get('after')
    elif event_name == 'pull_request':
        request = event.get('pull_request', {})
        base, head = request.get('base', {}).get('sha'), request.get('head', {}).get('sha')
    else:
        return True
    if any(not isinstance(sha, str) or not re.fullmatch('[0-9a-f]{40}', sha) or sha == '0' * 40
           for sha in (base, head)):
        return True
    try:
        difference = subprocess.run(['git', 'diff', '--name-only', '--no-renames', '-z', base, head],
                                    cwd=repository, check=True, capture_output=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return True
    documents = {'README.md', 'TECHNICAL.md', 'AGENTS.md', 'tests/manual-checks.md'}
    for raw in difference.split(b'\0'):
        if not raw:
            continue
        path = raw.decode('utf-8', errors='surrogateescape')
        parts = path.split('/')
        release_note = len(parts) == 2 and parts[0] == 'releases' and parts[1].endswith('.md')
        if path not in documents and not release_note:
            return True
    return False


def main():
    try:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        build = requires_build(event, os.environ.get('GITHUB_EVENT_NAME', ''), Path.cwd())
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        build = True
    result = 'true' if build else 'false'
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'build={result}\n')
    print('Mac builds required.' if build else 'Documentation only. Mac builds skipped.')


if __name__ == '__main__':
    main()
