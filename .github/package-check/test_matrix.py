import base64
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("matrix", Path(__file__).with_name("matrix.py"))
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class MatrixTests(unittest.TestCase):
    def test_powershell_literal(self):
        self.assertEqual(matrix.ps_quote("C:/a b/O'Brien"), "'C:/a b/O''Brien'")

    def test_encoded_command_roundtrip(self):
        text = "$env:R_HOME='C:/Program Files/R'; Write-Output 'ok'"
        encoded = matrix.powershell(text).split()[-1]
        self.assertEqual(base64.b64decode(encoded).decode("utf-16-le"), text)

    def test_nonzero_is_not_success(self):
        with tempfile.TemporaryFile(mode="w+") as log:
            with self.assertRaises(RuntimeError):
                matrix.run(["/bin/sh", "-c", "exit 7"], log)
            self.assertEqual(matrix.run(["/bin/sh", "-c", "exit 7"], log, False), 7)

    def test_invalid_target_name_is_rejected(self):
        with self.assertRaises(ValueError):
            matrix.execute({"name": "../escape"}, None, None, None, None, None)


if __name__ == "__main__":
    unittest.main()
