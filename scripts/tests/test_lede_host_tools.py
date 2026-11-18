"""Check dependency repair against old and updated LEDE tool graphs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

BASH = os.environ.get("BASH_EXE") or shutil.which("bash")
HOOK = Path(__file__).resolve().parents[1] / "lede-host-tools.sh"


@unittest.skipUnless(BASH, "bash is required for the LEDE hook")
class HostToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        self.makefile = self.root / "tools/Makefile"

    def run_hook(self):
        return subprocess.run(
            [BASH, HOOK.as_posix()], cwd=self.root,
            capture_output=True, text=True, check=False,
        )

    def check_graph(self, dependencies):
        original = "$(curdir)/elfutils/compile := " + dependencies + "\n"
        evaluation = "$(eval $(call subdir,$(curdir)))\n"
        self.makefile.write_text(original + evaluation, encoding="utf-8")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        repaired = self.makefile.read_text(encoding="utf-8")
        self.assertIn(original, repaired)
        extra = "$(curdir)/elfutils/compile += $(curdir)/bison/compile $(curdir)/flex/compile\n"
        self.assertIn(extra, repaired)
        self.assertLess(repaired.index(extra), repaired.index(evaluation))
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.makefile.read_text(encoding="utf-8"), repaired)

    def test_missing_parser_generators(self):
        self.check_graph("$(curdir)/m4/compile $(curdir)/libtool/compile")

    def test_upstream_already_requires_bison(self):
        self.check_graph("$(curdir)/bison/compile $(curdir)/libtool/compile")

    def test_unknown_layout_rejected(self):
        original = "tools-y += elfutils\n"
        self.makefile.write_text(original, encoding="utf-8")
        result = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dependency declaration changed", result.stderr)
        self.assertEqual(self.makefile.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
