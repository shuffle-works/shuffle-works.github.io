# Shuffle Works

Landing page for [Shuffle Works](https://shuffle-works.github.io), pointing to the SparkForensics, sparkenforce, and spark-tuning-reference projects.

Static site: plain HTML, CSS, and JS, no build step and no dependencies.

## Run locally

Open `index.html` directly, or serve the directory:

```
python -m http.server
```

The docs site under `sparkforensics/docs/` uses clean URLs (VitePress); `python -m http.server` doesn't resolve those without a trailing `.html`, so browsing docs links locally 404s. Use `npx serve` instead if you need to click through the docs.

## Deploy

Pushes to `main` publish automatically via GitHub Pages.
