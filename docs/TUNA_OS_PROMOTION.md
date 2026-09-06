# Promoting BlueShell to the tuna-os org + Flatpak remote

Goal: ship BlueShell through the TunaOS Flatpak remote
(`https://tunaos.org/flatpak/`, OCI images on `ghcr.io/tuna-os/*`, index
maintained in `tuna-os/docs` and served via Cloudflare Pages).

Repo-side groundwork in this tree is done:
`.github/workflows/publish-flatpak.yml` is committed and self-gates on
`github.repository == 'tuna-os/blueshell'`, so it activates on
transfer — nothing here blocks on the org. The remaining steps need
org permissions and are listed in order.

> **Status 2026-09-06: the transfer has NOT happened.** This document
> previously recorded step 1 as done on 2026-08-17; it is not. The repo
> is still `hanthor/blueshell`, which is why nothing has ever been
> published:
>
> - `publish-flatpak.yml` self-gates on
>   `github.repository == 'tuna-os/blueshell'`, so the job is skipped on
>   every push to `ptyxis-port`.
> - `org.tunaos.BlueShell` is absent from
>   `tuna-os/docs:static/flatpak/index/static`, so
>   `flatpak install tuna-os org.tunaos.BlueShell` fails with
>   "Nothing matches" — the remote is fine, the app was never added.
>
> Step 1 is the gate on everything below. Nothing publishes until it is
> real.

## 1. Transfer the repository — ⛔ NOT DONE

GitHub → repo **Settings → General → Danger Zone → Transfer ownership**
→ `tuna-os`. (Org owner must accept; hanthor needs create-repo rights
in the org or an owner initiates.) GitHub keeps redirects from the old
URL, so existing clones and the nightly.link install command keep
working during the switchover.

After transfer, in the new repo:

- Re-create the Actions secret(s): `FLATPAK_INDEX_TOKEN` — a PAT with
  write access to `tuna-os/docs` (used to register/update the app in
  the remote's index). Secrets do NOT transfer.
- Confirm Actions are enabled and `GITHUB_TOKEN` has `packages: write`
  (the publish workflow requests it, ghcr push needs it).
- Update the repo description/topics; keep the `upstream-sync` label
  (the daily sync workflow creates issues with it).

Two things are easy to miss here, and both are hard blockers:

- **`FLATPAK_INDEX_TOKEN` really is required.** Without it the publish
  job still builds and pushes the OCI images to GHCR, then skips the
  index update with a notice. The app never appears in the remote, so
  `flatpak install` keeps failing even though the run is green.
- **Make the GHCR packages public** after the first push
  (`ghcr.io/tuna-os/blueshell` and `ghcr.io/tuna-os/ghostty`). A private
  package is invisible to `flatpak`, with the same symptom.

## 2. Rename the app ID: `dev.hanthor.BlueShell` → `org.tunaos.BlueShell` — ✅ DONE

TunaOS convention is `org.tunaos.<App>`. One PR, mechanical:

| File | Change |
| --- | --- |
| `flatpak/org.tunaos.BlueShell.yml` | renamed file, `app-id:` field |
| `flatpak/org.tunaos.BlueShell.desktop` | renamed file; updated `Icon=` and `StartupWMClass=` |
| `flatpak/org.tunaos.BlueShell.svg` | renamed file (manifest install path follows app ID) |
| `.github/workflows/ghostty-ptyxis.yml` | `manifest-path`, bundle name |
| `.github/workflows/publish-flatpak.yml` | `APP_ID` env at the top |
| `README.md`, `HACKING.md` | install commands, App ID mention |

Notes:

- **Icon: done.** `flatpak/org.tunaos.BlueShell.svg` is original
  BlueShell artwork (blue scallop + terminal prompt), installed by the
  manifest under the app ID; `rename-icon` was dropped so Ghostty's
  unlicensed icon is no longer shipped. Rename the SVG alongside the
  app-id flip. `rename-appdata-file` still reuses upstream's metainfo —
  replace with a BlueShell metainfo file before Flathub-style listing
  polish matters.
- Keep `--own-name=com.mitchellh.ghostty` in `finish-args` for now: the
  GTK application still registers on D-Bus under upstream's id
  (invisible plumbing, not user-facing branding), and the
  single-instance guard silently exits without it. Longer-term, patch
  the app ID in the fork and add a `CONFLICT_HOTSPOTS.md` entry.
- Internal GObject class names (`GhosttyPtyxis*` in
  `src/apprt/gtk/class/` and their blueprint templates) are not
  user-facing and can be renamed to `BlueShell*` in a follow-up
  mechanical PR — not a blocker.
- Users of the old `dev.hanthor` install must
  `flatpak uninstall dev.hanthor.BlueShell` once; app IDs have no
  migration path.

## 3. Register in the TunaOS Flatpak remote

Per `tuna-os/flatpak-index` ("adding apps" flow):

1. Repo lives under `tuna-os/` — done by step 1.
2. Manifest at the expected path/name for the index tooling
   (`org.tunaos.BlueShell` — step 2). If the index tooling requires
   the manifest at repo root, add a thin root-level manifest that
   `base`s or mirrors `flatpak/org.tunaos.BlueShell.yml` rather
   than duplicating it.
3. CI workflow `publish-flatpak.yml` — already committed here, copied
   from `tuna-os/finupdate` (the canonical tuna-os pipeline): native
   x86_64 + aarch64 OCI builds in the GNOME 50 container → skopeo push
   to `ghcr.io/tuna-os/blueshell:latest-<arch>` → vendored
   `.github/scripts/update-index.py` updates
   `tuna-os/docs:static/flatpak/index/static` and pushes with
   `FLATPAK_INDEX_TOKEN`. Tags `v*` also attach .flatpak bundles to the
   GitHub release.
4. Set the secret (step 1) and push; Cloudflare Pages redeploys the
   index and the app appears in the remote.

Users then get it with:

```sh
flatpak remote-add --if-not-exists tuna-os https://tunaos.org/flatpak/tuna-os.flatpakrepo
flatpak install tuna-os org.tunaos.BlueShell
```

## 3b. Upstream Ghostty in the same remote

The remote also carries stock upstream Ghostty
(`com.mitchellh.ghostty`), published by
`.github/workflows/publish-ghostty-flatpak.yml`. It reuses the step-3
pipeline verbatim — same native per-arch OCI builds, same skopeo push,
same `update-index.py` against `tuna-os/docs` — with three differences:

- The app is built from a checkout of `ghostty-org/ghostty` using
  **upstream's own** manifest and `zig-packages.json`, so nothing about
  it is maintained in this repo and upstream dependency/runtime bumps
  need no action here.
- It runs on a daily cron (05:00 UTC) rather than on push, and
  short-circuits when the resolved upstream commit already has a
  `sha-<short>-x86_64` tag on `ghcr.io/tuna-os/ghostty`.
- The GHCR repo is `ghcr.io/tuna-os/ghostty`, so it needs its own index
  `Results` entry — `update-index.py` adds it on first run; the package
  itself must be made **public** in the org's package settings once, the
  same one-time step `blueshell` needs.

Because the app IDs differ, a user can install BlueShell and upstream
Ghostty side by side from the one remote.

## 4. tunaos.org site listing + install instructions

Being installable is not the finish line — the app must be discoverable:

1. **tunaos.org listing** — site changes are written and waiting in a
   PR against `tuna-os/docs`. The site is a Docusaurus build from that
   repo, and an app is listed in more places than the one page this
   document originally described:

   - `src/data/projects.ts` — the entry that drives the `/projects`
     card, the `/<app>` landing page, and `/install?app=<id>`.
   - `src/pages/<app>.tsx` — a thin wrapper over `ProjectLanding`.
   - `docs/<app>/index.md` — the reference page.
   - `sidebars.ts` — the entry under **Apps**.
   - `src/pages/flatpak.tsx` and `docs/flatpak/index.mdx` — both
     install catalogs.

   The PR covers BlueShell and Ghostty in all of the above. One trap it
   had to handle: `tuna-os/docs` runs `sync-org-docs.mjs`, which
   overwrites `docs/<slug>/` from each org repo's README
   unconditionally. `docs/blueshell/` was already such a tree. The PR
   adds both slugs to that script's `HAND_AUTHORED` set, without which
   the next sync replaces the page.

   `docs/site/blueshell/index.md` in this repo was the original draft
   for that page. The published copy now lives in `tuna-os/docs` and has
   moved on from it, so treat that file as history rather than a source
   to re-copy.

   Still worth adding once the app is live: a screenshot from the CI
   `ui-walkthrough` artifact (`02-prefs-appearance.png` shows the app
   best).

2. **README install instructions**: the README's "TunaOS Flatpak
   remote" section is already written (currently marked as pending
   promotion) — remove the "available once…" note and promote it to
   the recommended install path in the same PR that flips the app ID.

## 5. Publish runbook

The order matters: each step below is a hard prerequisite for the next,
and step 1 gates everything.

1. [ ] **Transfer the repo** to `tuna-os` (section 1). Until this
       happens every publish job self-skips and nothing reaches the
       remote.
2. [ ] **Set `FLATPAK_INDEX_TOKEN`** on the new repo — a PAT with push
       access to `tuna-os/docs`. Secrets do not survive a transfer. A
       run without it is green but publishes nothing to the index.
3. [ ] **Publish BlueShell.** Any push to `ptyxis-port` now triggers
       `publish-flatpak`; a `workflow_dispatch` does the same on
       demand.
4. [ ] **Publish Ghostty.** `publish-ghostty-flatpak` runs daily at
       05:00 UTC; dispatch it to avoid the wait.
5. [ ] **Make both GHCR packages public** —
       `ghcr.io/tuna-os/blueshell` and `ghcr.io/tuna-os/ghostty`. A
       private package fails to install exactly like a missing one.
6. [ ] **Confirm the index entries** landed in
       `tuna-os/docs:static/flatpak/index/static` (each publish job
       commits its own).
7. [ ] **Verify from a clean machine**:
       `flatpak install tuna-os org.tunaos.BlueShell` and
       `flatpak install tuna-os com.mitchellh.ghostty`.
8. [ ] **Merge the site PR** against `tuna-os/docs` (section 4). Do this
       after step 7: the pages present both install commands as working.
9. [ ] **Add both apps to `expected-apps.json`** in `tuna-os/docs`, with
       `archs: ["amd64", "arm64"]`. Deliberately not in the site PR:
       `check-flatpak-remote.py` fails on an app listed there but absent
       from the index, and `flatpak-sanity.yml` runs on every PR that
       touches `static/flatpak/**`. Once step 6 is real, this addition
       turns a standing warning into a check.
10. [ ] **README**: drop the "available once the promotion lands" note
        and make the remote the primary install path.
11. [ ] **Confirm the daily jobs** under the org: `upstream-sync.yml`
        can open issues and PRs, and `publish-ghostty-flatpak` finds its
        `sha-` tag and short-circuits on the second day.
12. [ ] Old repo redirect verified; announce the move in tunaOS
        channels.
