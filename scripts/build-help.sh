#!/bin/bash
set -euo pipefail

# Generate the offline licence from the original notice and index current Help.
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --skip-index ) ]]; then
    printf 'Usage: %s [--skip-index]\n' "$0" >&2
    exit 1
fi
: "${SRCROOT:?}"
: "${TARGET_BUILD_DIR:?}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
book="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/AlphaSync Help"
test -s "$book/alphasync-help.html"
test -s "$SRCROOT/../LICENSE"

{
    cat <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="KEYWORDS" content="licence, license, copyright, BSD, warranty">
    <meta name="description" content="AlphaSync’s original licence and copyright notice.">
    <link rel="stylesheet" href="css/alphasync.css">
    <title>Licence – AlphaSync Help</title>
</head>
<body>
<nav aria-label="Help navigation"><a href="alphasync-help.html">AlphaSync Help</a></nav>
<main>
<a id="alphasync-licence" name="alphasync-licence"></a>
<h1>Licence</h1>
<pre class="licence">
HTML
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$SRCROOT/../LICENSE"
    cat <<'HTML'
</pre>
</main>
</body>
</html>
HTML
} > "$book/licence.html"

python3 "$SRCROOT/../scripts/check-help.py" "$book" --licence-source "$SRCROOT/../LICENSE"
if [[ "${1:-}" != --skip-index ]]; then
    /usr/bin/hiutil -Caf "$book/AlphaSync Help.helpindex" "$book"
    printf 'Built the offline licence and current Help search index.\n'
fi
