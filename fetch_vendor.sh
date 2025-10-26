#!/usr/bin/env bash
set -e
mkdir -p assets/vendor
echo "Fetching vendor libraries into assets/vendor/ ..."

# highlight.js
curl -L -o assets/vendor/highlight.min.js "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"
curl -L -o assets/vendor/highlight.github-dark.min.css "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css"

# KaTeX
curl -L -o assets/vendor/katex.min.js "https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"
curl -L -o assets/vendor/katex.min.css "https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css"
curl -L -o assets/vendor/auto-render.min.js "https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"

# lazysizes
curl -L -o assets/vendor/lazysizes.min.js "https://cdnjs.cloudflare.com/ajax/libs/lazysizes/5.3.2/lazysizes.min.js"

# Simple Jekyll Search
curl -L -o assets/vendor/simple-jekyll-search.min.js "https://cdnjs.cloudflare.com/ajax/libs/simple-jekyll-search/1.11.1/simple-jekyll-search.min.js"

# Fuse.js (fuzzy search)
curl -L -o assets/vendor/fuse.min.js "https://cdnjs.cloudflare.com/ajax/libs/fuse.js/6.6.2/fuse.min.js"

# Noto Serif SC (CSS only) - you may need to download font files separately
curl -L -o assets/vendor/NotoSerifSC.css "https://fonts.itedev.com/NotoSerifSC/index.css"

echo "Done. Check assets/vendor/ for files."
