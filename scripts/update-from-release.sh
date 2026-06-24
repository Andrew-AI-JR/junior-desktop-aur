#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-Andrew-AI-JR/Desktop-Releases}"
PKGNAME="${PKGNAME:-junior-desktop}"
PKGBUILD="${PKGBUILD:-PKGBUILD}"

if [[ ! -f "$PKGBUILD" ]]; then
  echo "error: $PKGBUILD not found" >&2
  exit 1
fi

release_json="$(curl -fsSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest")"
tag_name="$(jq -r '.tag_name' <<<"$release_json")"
pkgver="${tag_name#v}"

deb_name="${PKGNAME}_${pkgver}_amd64.deb"
deb_asset="$(jq -r --arg name "$deb_name" '.assets[] | select(.name == $name)' <<<"$release_json")"

if [[ -z "$deb_asset" || "$deb_asset" == "null" ]]; then
  echo "error: release asset not found: $deb_name" >&2
  exit 1
fi

sha256="$(jq -r '.digest | sub("^sha256:"; "")' <<<"$deb_asset")"
if [[ -z "$sha256" || "$sha256" == "null" ]]; then
  echo "error: missing sha256 digest for $deb_name" >&2
  exit 1
fi

current_pkgver="$(grep -E '^pkgver=' "$PKGBUILD" | sed 's/^pkgver=//')"
current_sha256="$(grep -E "^sha256sums=" "$PKGBUILD" | sed -E "s/^sha256sums=\\('([^']*)'\\)/\\1/")"

if [[ "$pkgver" == "$current_pkgver" && "$sha256" == "$current_sha256" ]]; then
  echo "already up to date at ${pkgver}"
  exit 0
fi

echo "updating ${current_pkgver:-unknown} -> ${pkgver}"

sed -i "s/^pkgver=.*/pkgver=${pkgver}/" "$PKGBUILD"
sed -i 's/^pkgrel=.*/pkgrel=1/' "$PKGBUILD"
sed -i "s/^sha256sums=.*/sha256sums=('${sha256}')/" "$PKGBUILD"

if [[ "$(id -u)" -eq 0 ]]; then
  if ! id builduser >/dev/null 2>&1; then
    useradd -m builduser
  fi
  _tmp="$(mktemp -d)"
  cp PKGBUILD "$_tmp/"
  chown -R builduser:builduser "$_tmp"
  su builduser -c "cd '${_tmp}' && makepkg --printsrcinfo" > .SRCINFO
  rm -rf "$_tmp"
else
  makepkg --printsrcinfo > .SRCINFO
fi

echo "updated to ${pkgver} (${sha256})"
