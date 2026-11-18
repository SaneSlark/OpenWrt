#!/bin/bash
# Run from the LEDE source tree before its tools dependency graph is evaluated.
set -eu

dependency='$(curdir)/elfutils/compile += $(curdir)/bison/compile $(curdir)/flex/compile'
if grep -qxF "$dependency" tools/Makefile; then
  exit 0
fi
if ! grep -Eq '^\$\(curdir\)/elfutils/compile[[:space:]]*[:+]?=' tools/Makefile; then
  echo "LEDE elfutils dependency declaration changed; review tools/Makefile." >&2
  exit 1
fi
# Insert next to the existing declaration, before the subdir rules consume it.
# += also works when upstream has already added Bison to the original list.
sed -i '/^$(curdir)\/elfutils\/compile[[:space:]]*[:+]*=/a $(curdir)/elfutils/compile += $(curdir)/bison/compile $(curdir)/flex/compile' tools/Makefile
grep -qxF "$dependency" tools/Makefile
