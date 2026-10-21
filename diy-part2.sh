#!/bin/sh
# Run from the official OpenWrt source directory after installing feeds.
set -eu
chmod +x files/etc/init.d/lan-socks files/etc/uci-defaults/90-lan-socks files/usr/libexec/lan-socks-rules
