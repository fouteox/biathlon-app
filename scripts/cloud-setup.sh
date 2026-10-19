#!/bin/bash
# Installation de Swift pour l'environnement Claude Code cloud (Ubuntu 24.04).
# À coller dans « Setup script » de l'environnement cloud. Nécessite l'accès HTTPS à
# download.swift.org et keyserver.ubuntu.com.
# Reprend la méthode du Dockerfile officiel (github.com/swiftlang/swift-docker, 24.04) :
# archive officielle vérifiée par GPG, installée dans /usr. La clé est récupérée en HTTPS
# plutôt qu'en hkp:// (port 11371), bloqué dans l'environnement cloud.
set -euo pipefail

SWIFT_VERSION=6.4.1
# Swift 6.x Release Signing Key <swift-infrastructure@forums.swift.org>
SWIFT_SIGNING_KEY=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F

if command -v swift >/dev/null && swift --version 2>/dev/null | grep -qF "Swift version ${SWIFT_VERSION} ("; then exit 0; fi

export DEBIAN_FRONTEND=noninteractive
apt-get -q update
apt-get -q install -y curl binutils git unzip gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev \
  libz3-dev pkg-config tzdata zlib1g-dev

case "$(dpkg --print-architecture)" in
  amd64) SFX="" ;; arm64) SFX="-aarch64" ;; *) echo "arch non supportée" >&2; exit 1 ;;
esac
V="swift-${SWIFT_VERSION}-RELEASE"
URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404${SFX}/${V}/${V}-ubuntu24.04${SFX}.tar.gz"

WORK="$(mktemp -d)"; export GNUPGHOME="$(mktemp -d)"
curl -fsSL --retry 3 "$URL" -o "$WORK/swift.tar.gz"
curl -fsSL --retry 3 "$URL.sig" -o "$WORK/swift.tar.gz.sig"
curl -fsSL --retry 3 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${SWIFT_SIGNING_KEY}" -o "$WORK/swift.asc"
gpg --batch --quiet --import "$WORK/swift.asc"
gpg --batch --list-keys "$SWIFT_SIGNING_KEY" >/dev/null
gpg --batch --verify "$WORK/swift.tar.gz.sig" "$WORK/swift.tar.gz"
tar -xzf "$WORK/swift.tar.gz" --directory / --strip-components=1
chmod -R o+r /usr/lib/swift
rm -rf "$WORK" "$GNUPGHOME"
swift --version
# Échoue si un autre swift (ancien lien swiftly, etc.) passe avant /usr/bin dans le PATH.
swift --version 2>/dev/null | grep -qF "Swift version ${SWIFT_VERSION} (" || { echo "swift dans le PATH n'est pas ${SWIFT_VERSION}" >&2; exit 1; }
