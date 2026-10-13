# Swaddle website

The public site is maintained in `website/` in this app repository. It is a buildless static site: HTML, CSS, a small progressive enhancement script, and optimized local images. No framework, external fonts, analytics, cookies, or form backend.

- Home: https://swaddle-ios.app/
- Support: https://swaddle-ios.app/support/
- Privacy: https://swaddle-ios.app/privacy/

## Local preview and validation

```sh
python3 scripts/verify_website.py
python3 -m http.server 8769 --bind 127.0.0.1 --directory website
```

Serve from `website/`; do not open HTML with `file://`, because URLs are rooted at the custom domain. After changing CSS or JS, change their query version in each HTML page to invalidate cached assets.

Check desktop and phone layouts, keyboard navigation, FAQ disclosure controls, reduced-motion behavior, and links before publishing. Animations are decorative, finish quickly, and are disabled with the system's Reduce Motion preference. Core content and navigation work without JavaScript.

## Content and assets

The visual style follows `BabyActivityRecorder/Design/LogStyle.swift`: cream, forest, sage, blue, amber, editorial serif headings, and native system text. Screens are unaltered Simulator captures with fictional Robin/Sam/Alex data from the App Store QA fixture. WebP copies are resized for the website. The app's Cocoon mark is reused with its original artwork.

The entire `website/` folder is public. Never place family records, diagnostics, credentials, archives, or internal QA reports in it.

The App Store launch is pending, so the site deliberately uses “Coming to the App Store.” When the app's public listing is available, replace the launch notes and download FAQ with the verified App Store link and update the software metadata. Do not add fabricated ratings, reviews, medical claims, or download counts.

Public contact uses the email already displayed on Fedor's public GitHub profile. Update it in both legal/support pages if the owner selects another address. A `support@` address must not be advertised until it can receive email.

## Hosting

GitHub Pages hosts the site; Cloudflare manages `swaddle-ios.app` DNS. The custom domain belongs to the Pages configuration before DNS is pointed there. Apex and `www` use GitHub's documented records, with HTTPS enforced after GitHub provisions its certificate. Keep unrelated DNS records intact.

The private repository at https://github.com/fkorotkov/swaddle-ios.app contains the iOS app and website together on `main`. The workflow in `.github/workflows/website.yml` publishes only `website/`; no separate website branch or repository is needed. GitHub Pro (or another eligible plan) is required for Pages from a private repository.

**Hosting status, October 13, 2026:** GitHub disabled Pages after the repository became private. Its API rejects enabling Pages with “Your current plan does not support GitHub Pages for this repository.” The domain currently returns 404. The website artifact passed verification (only the 24 public files). Restoration is awaiting the owner's choice between a GitHub plan upgrade and Cloudflare Pages. Do not make this repository public to restore the site: it now contains the app source.

The initial app upload is a clean snapshot of the current source, tests, resources, reference data, and build configuration. Local build products, signing credentials, family exports, design experiments, and release/QA evidence are excluded. The older local app history is retained locally, not pushed to GitHub. Never publish the repository root as a Pages artifact.

To publish updates from this app checkout:

```sh
python3 scripts/publish_website.py
gh run list --repo fkorotkov/swaddle-ios.app --limit 3
```

Normal commits to `main` that change the website trigger deployment. The helper above is also available for publishing only website changes from a dirty app checkout: it validates locally, clones the same private repository into a temporary directory, copies an explicit website allowlist, validates again, and pushes a website commit. It preserves app files and never copies local Git history. Fetch the resulting commit before the next app push. Check the resulting GitHub Actions deployment before declaring an update live.

Domain DNS: four GitHub Pages A records and four AAAA records at the apex; `www` is a CNAME to `fkorotkov.github.io`. Records are DNS-only in Cloudflare. GitHub manages the site certificate and the `www` redirect. No wildcard DNS or email settings were added.

SEO includes crawlable HTML, unique titles/descriptions, canonical URLs, social previews, descriptive image text, SoftwareApplication structured data, robots.txt, and a sitemap. These help discovery; they do not guarantee indexing, rich results, or search ranking.
