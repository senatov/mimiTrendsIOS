"""Check that release notes cover every commit after the last published tag."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_notes import previous_release, release_notes  # noqa: E402


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.old_directory = Path.cwd()
        os.chdir(self.temporary.name)
        self.run_git("init", "-q")
        self.run_git("config", "user.email", "release-test@example.test")
        self.run_git("config", "user.name", "Release Test")

    def tearDown(self) -> None:
        os.chdir(self.old_directory)
        self.temporary.cleanup()

    def run_git(self, *args: str) -> str:
        return subprocess.check_output(["git", *args], text=True).strip()

    def commit(self, subject: str, body: str = "") -> None:
        file = Path("changes.txt")
        file.write_text(file.read_text() + subject + "\n" if file.exists() else subject + "\n")
        self.run_git("add", "changes.txt")
        command = ["commit", "-q", "-m", subject]
        if body:
            command.extend(["-m", body])
        self.run_git(*command)

    def test_notes_include_every_intervening_commit_and_body(self) -> None:
        self.commit("Before first release")
        self.run_git("tag", "0.0.1.1")
        self.commit("FIX: repair scanner", "Explain why the scanner was repaired.")
        self.commit("NEW: add chart")
        self.run_git("tag", "0.0.1.2")

        self.assertEqual(previous_release(["unrelated", "0.0.1.1"]), "0.0.1.1")
        self.assertEqual(previous_release(["0.0.1.1", "0.0.1.2"]), "0.0.1.2")
        notes = release_notes("0.0.1.1", "0.0.1.2")
        self.assertNotIn("Before first release", notes)
        self.assertIn("FIX: repair scanner", notes)
        self.assertIn("Explain why the scanner was repaired.", notes)
        self.assertIn("NEW: add chart", notes)
        self.assertLess(notes.index("FIX: repair scanner"), notes.index("NEW: add chart"))
        self.assertIn("/compare/0.0.1.1...0.0.1.2", notes)

    def test_initial_release_includes_full_history(self) -> None:
        self.commit("First change")
        self.commit("Second change")
        self.run_git("tag", "0.0.0.1")
        notes = release_notes("", "0.0.0.1")
        self.assertIn("First change", notes)
        self.assertIn("Second change", notes)
        self.assertIn("Initial release changes", notes)


if __name__ == "__main__":
    unittest.main()
