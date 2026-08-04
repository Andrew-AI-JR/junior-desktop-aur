#!/usr/bin/env bash
set -euo pipefail

PKGNAME="${PKGNAME:-junior-desktop}"
PKGBUILD="${PKGBUILD:-PKGBUILD}"
SRCINFO="${SRCINFO:-.SRCINFO}"
AUR_HOST="${AUR_HOST:-aur.archlinux.org}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-Update PKGBUILD and .SRCINFO}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

: "${AUR_SSH_PRIVATE_KEY:?AUR_SSH_PRIVATE_KEY is required}"
: "${AUR_USERNAME:?AUR_USERNAME is required}"
: "${AUR_EMAIL:?AUR_EMAIL is required}"

if [[ ! -f "$PKGBUILD" || ! -f "$SRCINFO" ]]; then
  echo "error: missing $PKGBUILD or $SRCINFO" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "maintenance=false" >>"$GITHUB_OUTPUT"
fi

skip_for_maintenance() {
  echo "AUR is under maintenance; skipping publish without failing" >&2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "maintenance=true" >>"$GITHUB_OUTPUT"
  fi
  exit 0
}

is_aur_maintenance() {
  local log=$1
  grep -qi 'AUR is down due to maintenance' "$log"
}

# Official AUR SSH fingerprints from https://aur.archlinux.org/
expected_fps=(
  'SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4'
  'SHA256:uTa/0PndEgPZTf76e1DFqXKJEXKsn7m9ivhLQtzGOCI'
  'SHA256:5s5cIyReIfNNVGRFdDbe3hdYiI5OelHGpw2rOUud3Q8'
)

ssh_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$ssh_dir" "${workdir:-}"
}
trap cleanup EXIT

mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
printf '%s\n' "$AUR_SSH_PRIVATE_KEY" >"$ssh_dir/aur"
chmod 600 "$ssh_dir/aur"

scanned="$ssh_dir/scanned"
ssh-keyscan -t rsa,ecdsa,ed25519 "$AUR_HOST" >"$scanned" 2>/dev/null
if [[ ! -s "$scanned" ]]; then
  echo "error: ssh-keyscan returned no host keys for $AUR_HOST" >&2
  exit 1
fi

mapfile -t fingerprints < <(ssh-keygen -lf "$scanned" | awk '{print $2}')
if [[ "${#fingerprints[@]}" -eq 0 ]]; then
  echo "error: ssh-keygen produced no fingerprints for $AUR_HOST" >&2
  exit 1
fi

for fp in "${fingerprints[@]}"; do
  matched=false
  for expected in "${expected_fps[@]}"; do
    if [[ "$fp" == "$expected" ]]; then
      matched=true
      break
    fi
  done
  if [[ "$matched" != true ]]; then
    echo "error: unexpected SSH host key fingerprint for $AUR_HOST: $fp" >&2
    exit 1
  fi
  echo "verified host key: $fp"
done

mv "$scanned" "$ssh_dir/known_hosts"
chmod 600 "$ssh_dir/known_hosts"

export GIT_SSH_COMMAND="ssh -i ${ssh_dir}/aur -o IdentitiesOnly=yes -o UserKnownHostsFile=${ssh_dir}/known_hosts -o StrictHostKeyChecking=yes"

workdir="$(mktemp -d)"
aur_url="ssh://aur@${AUR_HOST}/${PKGNAME}.git"
git_log="$ssh_dir/git.log"

attempt=1
while true; do
  rm -rf "$workdir/repo"
  if git clone "$aur_url" "$workdir/repo" >"$git_log" 2>&1; then
    break
  fi
  cat "$git_log" >&2
  if is_aur_maintenance "$git_log"; then
    skip_for_maintenance
  fi
  if [[ "$attempt" -ge "$MAX_ATTEMPTS" ]]; then
    echo "error: failed to clone $aur_url after ${MAX_ATTEMPTS} attempts" >&2
    exit 1
  fi
  echo "clone attempt ${attempt} failed, retrying..." >&2
  attempt=$((attempt + 1))
  sleep $((attempt * 5))
done

cp "$PKGBUILD" "$workdir/repo/PKGBUILD"
cp "$SRCINFO" "$workdir/repo/.SRCINFO"

git -C "$workdir/repo" config user.name "$AUR_USERNAME"
git -C "$workdir/repo" config user.email "$AUR_EMAIL"
git -C "$workdir/repo" add PKGBUILD .SRCINFO

if git -C "$workdir/repo" diff --cached --quiet; then
  echo "AUR package already up to date"
  exit 0
fi

git -C "$workdir/repo" commit -m "$COMMIT_MESSAGE"

attempt=1
while true; do
  if git -C "$workdir/repo" push origin HEAD:master >"$git_log" 2>&1; then
    cat "$git_log"
    echo "published ${PKGNAME} to AUR"
    exit 0
  fi
  cat "$git_log" >&2
  if is_aur_maintenance "$git_log"; then
    skip_for_maintenance
  fi
  if [[ "$attempt" -ge "$MAX_ATTEMPTS" ]]; then
    echo "error: failed to push to AUR after ${MAX_ATTEMPTS} attempts" >&2
    exit 1
  fi
  echo "push attempt ${attempt} failed, retrying..." >&2
  attempt=$((attempt + 1))
  sleep $((attempt * 5))
done
