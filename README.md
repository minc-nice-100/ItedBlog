# Noctua v3 Offline (ItedBlog)

This package contains a complete Jekyll theme configured for pure Markdown writing.
It includes **placeholder** vendor files and a `fetch_vendor.sh` script to download
the official minified libraries into `assets/vendor/` so the site can run fully offline.

How to install:
1. Unzip into your blog repo root (ItedBlog).
2. Run `./fetch_vendor.sh` (requires curl) to download real vendor files.
3. Optionally upload `assets/` to your CDN and set `cdn_base` in `_config.yml`.
4. Run `bundle exec jekyll serve` to test locally.

Files you may want to replace:
- assets/vendor/* : placeholder JS/CSS. Run fetch script to replace with official builds.

If you want me to fetch the real vendor files and embed fonts for you, I can attempt it,
but I cannot access your GitHub; instead I will produce the package and a fetch script.
