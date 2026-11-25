"""Regression tests for the non-destructive Mossling PNG strip validator."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[1]
SPEC = spec_from_file_location(
    "validate_mossling_art_sources",
    PROJECT / "tools" / "validate_mossling_art_sources.py",
)
VALIDATOR = module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class MosslingStripValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "strip.png"

    def save_frames(self, frames):
        strip = Image.new("RGBA", (96 * len(frames), 128), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            strip.alpha_composite(frame, (index * 96, 0))
        strip.save(self.path)
        return self.path

    @staticmethod
    def marked_frame(x, y):
        frame = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rectangle((x, y, x + 8, y + 8), fill=(90, 160, 40, 255))
        return frame

    def test_accepts_distinct_nonempty_frames(self):
        path = self.save_frames([self.marked_frame(10, 10), self.marked_frame(30, 20)])
        self.assertEqual(VALIDATOR.validate_strip(path, 2), [])

    def test_rejects_exact_duplicate_frames(self):
        frame = self.marked_frame(10, 10)
        path = self.save_frames([frame, frame.copy()])
        problems = VALIDATOR.validate_strip(path, 2)
        self.assertTrue(any("duplicates an earlier frame exactly" in item for item in problems))

    def test_rejects_fully_transparent_frame(self):
        path = self.save_frames([self.marked_frame(10, 10), Image.new("RGBA", (96, 128))])
        problems = VALIDATOR.validate_strip(path, 2)
        self.assertTrue(any("fully transparent" in item for item in problems))

    def test_rejects_wrong_dimensions(self):
        Image.new("RGBA", (96, 128), (0, 0, 0, 0)).save(self.path)
        problems = VALIDATOR.validate_strip(self.path, 2)
        self.assertTrue(any("expected" in item for item in problems))

    def test_rejects_opaque_top_left_pixel(self):
        frame = self.marked_frame(10, 10)
        frame.putpixel((0, 0), (255, 255, 255, 255))
        path = self.save_frames([frame])
        problems = VALIDATOR.validate_strip(path, 1)
        self.assertTrue(any("top-left canvas pixel" in item for item in problems))


if __name__ == "__main__":
    unittest.main(verbosity=2)
