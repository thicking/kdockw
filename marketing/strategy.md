# KDockW Marketing & SEO Strategy

## Target Audience

### Primary
- **Former Latte Dock users** who lost their dock when upgrading to KDE Plasma 6
- Pain point: Latte Dock is discontinued, no Plasma 6 support
- Estimated reach: Latte Dock had significant adoption across KDE community

### Secondary
- **KDE Plasma users** who want a more feature-rich dock than the default panel
- **Linux customizers** (r/unixporn community) seeking aesthetic desktop setups
- **macOS converts** looking for familiar dock behavior on Linux

## SEO Keywords

### Primary (Use in README, metainfo, all public-facing text)
- kde plasma dock
- latte dock alternative
- kde plasma 6 dock
- plasma 6 dock

### Secondary
- wayland dock linux
- kde dock application
- linux dock app
- kde taskbar replacement
- macos dock linux

### Long-tail
- latte dock plasma 6 alternative
- best dock for kde plasma
- lightweight dock kde plasma
- parabolic zoom dock linux
- pipewire window preview dock

## Distribution Channels

### Tier 1: Direct Target Audience (Launch Day)

| Channel | Format | Notes |
|---------|--------|-------|
| r/kde | Announcement post | Primary target audience, include screenshots |
| r/linux | Self-post with features | Broader Linux community |
| r/unixporn | Rice screenshot | Visual showcase, link to repo in comments |
| KDE Discuss | Announcement thread | Official KDE community |

### Tier 2: Tech Community (Launch Week)

| Channel | Format | Notes |
|---------|--------|-------|
| Hacker News | Show HN post | Technical audience, emphasize architecture |
| Mastodon (#KDE #Linux) | Thread with screenshots | FOSS community |

### Tier 3: Press & Media (Post-Launch)

| Channel | Approach | Notes |
|---------|----------|-------|
| Phoronix | Tip submission | Linux hardware/software news |
| OMG! Linux | Press pitch | Ubuntu-focused but covers KDE |
| It's FOSS | Article pitch | Beginner-friendly Linux media |
| LWN.net | Brief mention | Technical Linux news |

## Launch Readiness Checklist

Before any public announcement:

- [x] All M7 and M8 items complete (attention animations, icon normalization, multi-monitor)
- [x] Three owner-provided KDockW screenshots are in the README gallery; the site build publishes these same files
- [x] Existing KDockW demo video is linked from README and included in the Pages site
- [x] GitHub Releases is the only publication channel; platform package builds remain attached to releases
- [x] Positioning manifest current (`marketing/positioning.yml`)
- [ ] Blog post drafted (origin story + features)
- [x] Drafts prepared for r/kde and r/unixporn; r/linux remains optional and unpublished
- [x] KDE Discuss announcement drafted

## Content Calendar (Post-Launch)

| Timing | Content | Channel |
|--------|---------|---------|
| Launch Day | Announcement post | r/kde, r/linux, KDE Discuss |
| Launch Day | Visual showcase | r/unixporn |
| Launch Day | Show HN | Hacker News |
| Week 1 | "Developing a spiritual successor to Latte Dock" blog post | Blog, Mastodon |
| Week 2 | Technical deep-dive (PipeWire previews) | Blog, r/kde |
| Week 4 | Feature comparison (KDockW vs alternatives) | Blog, r/linux |
| Monthly | Release notes / progress update | r/kde, KDE Discuss |

## SEO Optimization Status

### GitHub Repository
- [x] Description with primary keywords
- [x] 11 repository topics, verified against GitHub API
- [x] Homepage set to https://thicking.github.io/kdockw/
- [x] README with badges, features, installation
- [x] LICENSE file
- [x] English documentation
- [x] Active-development status badge for transparency

### App Store / Package Manager
- [x] metainfo.xml with keywords element
- [x] .desktop file with Keywords field
- [x] Expanded multi-paragraph description in metainfo.xml
- [x] Screenshots in metainfo.xml (for KDE Discover)

### Website & Social
- [x] Deploy and verify the refreshed site: [Pages run 42468222323](https://github.com/thicking/kdockw/actions/runs/42468222323). The page, CSS, icons, OG image, screenshots, MP4, `robots.txt`, and sitemap returned HTTP 200.
- [x] Current KDockW OpenGraph preview (`website/og-image.png`)
- [x] The deployed Pages site serves three screenshots and the existing MP4 demo

### Future
- [ ] Blog with SEO-optimized articles


### Discovery work (2026-11)

- GitHub About description, homepage URL, and 11 topics were checked against the live GitHub API and updated to match `marketing/positioning.yml`.
- Search Console and Bing Webmaster account access was not available in this environment. The public sitemap and `robots.txt` are reachable. Sampled public search queries returned no results; this does not prove the site is absent from either index.
- The Pages site deployed on main commit `5c29dd6d8ede819bad094c2a0f42dd9146c3d282` (run 42468222323).
- No posts were published. Prepared drafts are in `marketing/discovery-drafts.md`.
- KDE Store/Pling is a possible discovery listing for libre software, but no KDockW listing was found or submitted. See the provider's [creator FAQ](https://store.kde.org/faq-pling); account ownership and any listing decision remain with the project owner.
