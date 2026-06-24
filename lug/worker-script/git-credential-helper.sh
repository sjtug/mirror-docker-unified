#!/bin/sh
# git-credential-readonly — read-only credential store helper
#
# A drop-in replacement for git-credential-store that only handles `get`
# (by reading the credential file) and silently ignores `store`/`erase`.
# Safe to use when the credential file is a read-only bind mount.
#
# Usage:
#   git config --global credential.helper readonly
#
# Design: delegates `get` to `git credential-store --file <file> get`
# (which only reads, never writes), and ignores `store`/`erase`.
#
# See also:
#   https://github.com/ttys3/git-credential-readonly
#   https://github.com/nzlosh/git-credentials-readonly

set -eu

cred_file="${HOME}/.git-credentials"

case "${1:-}" in
    get)
        if [ -f "$cred_file" ] && [ -r "$cred_file" ]; then
            exec git credential-store --file "$cred_file" get
        fi
        exit 0
        ;;
    store|erase)
        # No-op: never write to the credential store (read-only bind mount).
        exit 0
        ;;
    *)
        echo "usage: git credential-readonly <get|store|erase>" >&2
        exit 1
        ;;
esac
