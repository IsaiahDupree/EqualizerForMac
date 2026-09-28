import dataclasses
import unittest

import metadata


class MetadataValidationTests(unittest.TestCase):
    def test_shipping_copy_obeys_apple_limits(self):
        metadata.validate_all()

    def test_french_keywords_use_the_full_byte_budget(self):
        self.assertEqual(len(metadata.LOCALIZATIONS["fr-FR"].keywords.encode("utf-8")), 100)

    def test_rejects_repeated_visible_keyword(self):
        original = metadata.LOCALIZATIONS["en-US"]
        invalid = dataclasses.replace(original, keywords=original.keywords + ",Mac")
        with self.assertRaisesRegex(ValueError, "repeat indexed title/subtitle words"):
            metadata.validate_copy(invalid)

    def test_rejects_keyword_field_over_100_bytes(self):
        original = metadata.LOCALIZATIONS["fr-FR"]
        invalid = dataclasses.replace(original, keywords=original.keywords + ",grave")
        with self.assertRaisesRegex(ValueError, "max 100"):
            metadata.validate_copy(invalid)


if __name__ == "__main__":
    unittest.main()
