# Staying in sync with upstream Ghostty

BlueShell is a patch-set on top of `ghostty-org/ghostty`. The whole
strategy is built around one goal: **keep the downstream diff small,
mechanical to re-apply, and loudly alarmed** so the daily rebase stays a
15-minute chore instead of a rescue mission.

## The four pillars

### 1. Automated daily rebase — `.github/workflows/upstream-sync.yml`

Every day at 07:00 UTC (and on manual dispatch) CI fetches
`ghostty-org/ghostty:main` and attempts `git rebase` of `ptyxis-port`:

- **Clean rebase** → pushes `upstream-sync/<date>` and opens a PR
  against `ptyxis-port`. Merge it after CI (`ptyxis-tests` +
  `ghostty-ptyxis` flatpak) is green. Merging it also fires
  `publish-flatpak`, so the BlueShell build on the TunaOS remote
  carries the imported upstream changes.
- **Conflicts** → opens an issue labeled `upstream-sync` listing the
  conflicted files and the upstream commit range, with local
  reproduction steps.

The run is a no-op when `ptyxis-port` already contains upstream's HEAD,
and it also **stands down while an `upstream-sync/*` PR is still open**
— otherwise a daily cadence would stack a second branch and PR on an
overlapping commit range every morning. Merge or close the open one and
the next run resumes. Daily rather than weekly is the whole point: a
one-day diff conflicts far less often than a seven-day one, and when it
does the range to reason about is a single day of upstream commits.

### 2. The conflict map — `CONFLICT_HOTSPOTS.md`

Every upstream file we modify is listed there with *what* we changed,
*why it can break*, and a *resolution recipe*. When the sync run flags a
conflict, resolve using the recipe, and keep the file honest:

- Touch a new upstream file → add an entry in the same PR.
- Drop a patch (e.g. it was upstreamed) → delete the entry in the same
  commit.

### 3. Additions over modifications

Fork code lives in **new files** wherever possible
(`preferences_window.zig`, `preferences_logic.zig`, `profile_store.zig`,
`config_bridge.zig`, `test/ui/`, workflows). New files can't conflict.
The residual patches to upstream files are deliberately tiny and
documented in the hotspots map. When a patch could serve upstream, send
it upstream (see issue #6 pattern) — every accepted patch is a hotspot
entry deleted forever.

### 4. Drift alarms — the test suite

Rebases that *merge cleanly but break behavior* are the dangerous ones.
The fork's tests (see `TESTING.md`) are written to convert silent drift
into red CI on the sync PR:

- Every preference-UI combo table is checked **bidirectionally** against
  the corresponding upstream config enum: an upstream member added,
  renamed, or removed fails `preferences_logic` tests even though no
  file conflicted.
- Everything the UI writes is re-parsed by upstream's real config
  parser with zero-diagnostic assertions, so upstream key renames or
  syntax changes surface immediately.
- The headless smoke test catches blueprint/libadwaita/template
  breakage from upstream UI-toolkit bumps.

## Operator playbook

Each morning, when the sync PR/issue arrives:

1. **PR, CI green** → merge. Done.
2. **PR, CI red** → the diff merged but semantics drifted; the failing
   test names point at the table/key to update (usually a one-line
   table + blueprint string-list addition).
3. **Issue (conflicts)** → follow the reproduction block in the issue,
   resolve each file with its `CONFLICT_HOTSPOTS.md` recipe, push the
   branch, open the PR, let CI vouch for it.

Tracking upstream **releases** instead of `main` is a deliberate
non-goal while the fork iterates quickly; if that changes, point the
workflow's `fetch upstream main` at the release tag instead.

## Publishing upstream Ghostty alongside BlueShell

`.github/workflows/publish-ghostty-flatpak.yml` builds **unmodified
upstream Ghostty** (`com.mitchellh.ghostty`) daily at 05:00 UTC and
publishes it to the same TunaOS Flatpak remote as BlueShell, so users
can install either terminal — or both — from one remote:

```sh
flatpak install tuna-os com.mitchellh.ghostty
```

It shares no source with this fork. The workflow checks out
`ghostty-org/ghostty` at the requested ref (`main` by default) and
builds with **upstream's own** `flatpak/com.mitchellh.ghostty.yml` and
`flatpak/zig-packages.json`, reading the GNOME runtime version out of
that manifest to pick the builder image. That is what keeps it in sync
by construction: there is no manifest, no dependency pin, and no runtime
version maintained here, so upstream bumping any of them is picked up by
the next daily run with no change to this repo.

Each run pushes `ghcr.io/tuna-os/ghostty:latest-<arch>` plus an
immutable `sha-<upstream-short>-<arch>` tag. That pinned tag is also the
idempotency check: a daily run whose upstream commit is already
published exits in seconds instead of spending two full Zig builds.
Rebuild one anyway with the workflow's `force` dispatch input.

The vendored `flatpak/com.mitchellh.ghostty.yml` in *this* repo is a
different thing — it is upstream's manifest carried along by the fork
for local builds and is not what the publish workflow uses.
