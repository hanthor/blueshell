#!/usr/bin/env bash
# Tiny GHCR registry helpers for workflows, sourced (not executed).
#
# Deliberately curl-only: the ubuntu runner images don't ship skopeo by
# default, and a tag-existence check shouldn't need a container tool
# installed just to answer "have we published this commit already?".

# ghcr_tag_exists <owner/repo> <tag>
#
# Returns 0 if the tag resolves to a manifest, 1 if it 404s. Uses
# GITHUB_TOKEN when set (required for private packages); public images
# resolve fine with the anonymous pull token GHCR hands out to anyone.
ghcr_tag_exists() {
  local repo="$1" tag="$2" token http

  local -a auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-u "x:${GITHUB_TOKEN}")
  fi

  token=$(curl -fsSL "${auth[@]}" \
    "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull" \
    | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("token", ""))
except Exception:
    pass') || return 1
  [ -n "$token" ] || return 1

  http=$(curl -sSL -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/${repo}/manifests/${tag}")

  [ "$http" = "200" ]
}
