#!/usr/bin/env bash
# Tiny GHCR registry helpers for workflows, sourced (not executed).
#
# Deliberately curl-only: the ubuntu runner images don't ship skopeo by
# default, and a tag-existence check shouldn't need a container tool
# installed just to answer "have we published this commit already?".

# _ghcr_token <owner/repo>
#
# Echoes a pull token for the repo, or nothing.
#
# Anonymous first, on purpose. Anonymous covers every public package, and
# GHCR is picky about the authenticated form: a placeholder username is
# rejected outright with 403 (`-u x:$GITHUB_TOKEN` fails even inside
# Actions with packages:write). The real actor is what it accepts, so the
# authenticated retry is only worth making when Actions gives us one —
# and it is only *needed* for a package that is still private.
_ghcr_token() {
  local repo="$1"
  local url="https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull"
  local body

  body=$(curl -fsSL "$url" 2>/dev/null) || body=""

  if [ -z "$body" ] && [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_ACTOR:-}" ]; then
    body=$(curl -fsSL -u "${GITHUB_ACTOR}:${GITHUB_TOKEN}" "$url" 2>/dev/null) || body=""
  fi

  [ -n "$body" ] || return 1
  printf '%s' "$body" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("token", ""))
except Exception:
    pass'
}

# ghcr_tag_exists <owner/repo> <tag>
#
# Returns 0 if the tag resolves to a manifest, non-zero otherwise —
# including when the registry cannot be reached at all. Callers use this
# to skip work that has already been done, so "don't know" and "not
# there" must both mean "do the work": a wasted rebuild is cheap, a
# silently skipped publish is not.
ghcr_tag_exists() {
  local repo="$1" tag="$2" token http

  token=$(_ghcr_token "$repo") || {
    echo "ghcr: no pull token for ${repo} — treating ${tag} as absent" >&2
    return 1
  }
  if [ -z "$token" ]; then
    echo "ghcr: empty pull token for ${repo} — treating ${tag} as absent" >&2
    return 1
  fi

  http=$(curl -sSL -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${repo}/manifests/${tag}")

  echo "ghcr: ${repo}:${tag} -> HTTP ${http}" >&2
  [ "$http" = "200" ]
}
