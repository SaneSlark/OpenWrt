#!/usr/bin/env python3
"""Bundle the latest stable Mihomo core for these x86_64 firmware profiles."""
import gzip
import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.request


def fetch(url):
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "OpenWrt-builder"})
            with urllib.request.urlopen(request, timeout=180) as response:
                return response.read()
        except OSError:
            if attempt == 2:
                raise
            time.sleep(2)


def main():
    root = Path(sys.argv[1])
    if "CONFIG_TARGET_x86_64=y" not in (root / ".config").read_text(encoding="utf-8"):
        raise SystemExit("The bundled core requires the x86_64 target")
    core = root / "files/etc/openclash/core/clash_meta"
    # The LEDE workflow can invoke the post hook more than once.
    if core.exists():
        return
    release = json.loads(fetch("https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"))
    name = f"mihomo-linux-amd64-compatible-{release['tag_name']}.gz"
    asset = next(item for item in release["assets"] if item["name"] == name)
    digest = asset.get("digest", "")
    if not digest or not digest.startswith("sha256:"):
        raise SystemExit("Upstream SHA256 digest missing; refusing an unverified core")
    archive = fetch(asset["browser_download_url"])
    if hashlib.sha256(archive).hexdigest() != digest.removeprefix("sha256:"):
        raise SystemExit("Mihomo SHA256 verification failed")
    binary = gzip.decompress(archive)
    if not binary.startswith(b"\x7fELF"):
        raise SystemExit("Mihomo asset is not an ELF binary")
    core.parent.mkdir(parents=True, exist_ok=True)
    core.write_bytes(binary)
    core.chmod(0o755)
    (root / "openclash-core-version.txt").write_text(
        f"{release['tag_name']}\n{asset['browser_download_url']}\n{digest}\n", encoding="utf-8"
    )
    print(f"Bundled verified Mihomo {release['tag_name']} for OpenClash")


if __name__ == "__main__":
    main()
