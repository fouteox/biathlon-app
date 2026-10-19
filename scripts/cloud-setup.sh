#!/bin/bash
# Script d'installation de Swift pour l'environnement Claude Code cloud (Ubuntu 24.04).
# À coller dans « Setup script » de l'environnement cloud. Nécessite download.swift.org
# dans les domaines autorisés.
set -euo pipefail

SWIFT_VERSION=6.4.1

apt-get update -qq
apt-get install -y -qq binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev \
  libz3-dev pkg-config tzdata unzip zlib1g-dev

cd /tmp
curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
tar zxf "swiftly-$(uname -m).tar.gz"
./swiftly init --assume-yes --quiet-shell-followup --skip-install
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
swiftly install "$SWIFT_VERSION" --use --assume-yes

# Rend swift disponible dans tous les shells, sans sourcer env.sh.
ln -sf "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/bin/"* /usr/local/bin/
swift --version
