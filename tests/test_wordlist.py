"""Verify that compact data preserves the complete licensed lexicon."""
import math
from pathlib import Path
import re
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from wordlist import compile_words, pack, read_words

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'games/wordle/words.txt'
ANSWERS = ROOT / 'games/wordle/answers.txt'


class WordlistTests(unittest.TestCase):
    def test_every_dictionary_word_round_trips(self):
        words = read_words(SOURCE)
        offsets, data = pack(words)
        decoded = []
        for initial in range(26):
            pos, value = offsets[initial], 0
            while pos < offsets[initial+1]:
                shift, delta = 0, 0
                while True:
                    part = data[pos]; pos += 1
                    delta |= (part & 127) << shift
                    if not part & 128:
                        break
                    shift += 7
                value += delta
                suffix, n = '', value
                for _ in range(4):
                    n, letter = divmod(n, 26)
                    suffix = chr(65+letter) + suffix
                decoded.append(chr(65+initial) + suffix)
            self.assertEqual(pos, offsets[initial+1])
        self.assertEqual(decoded, sorted(words))

    def test_all_answer_codes_and_puzzle_ids(self):
        words, answers = read_words(SOURCE), read_words(ANSWERS)
        self.assertEqual(math.gcd(73, len(answers)), 1)
        self.assertEqual(len({((i-1)*73) % len(answers) for i in range(1,len(answers)+1)}), len(answers))
        with tempfile.TemporaryDirectory() as directory:
            header = Path(directory) / 'dictionary.h'
            compile_words(SOURCE, ANSWERS, header)
            section = header.read_text().split('answer_codes[ANSWER_COUNT] = {')[1]
            codes = [int(n) for n in re.findall(r'(\d+)U,', section)]
            self.assertEqual(len(codes), len(answers))
            for expected, code in zip(answers, codes):
                initial = chr(65+(code >> 11))
                bucket = sorted(w for w in words if w[0] == initial)
                self.assertEqual(bucket[code & 2047], expected)

    def test_bad_dictionary_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'words.txt'
            for text in ('APPLE\nAPPLE\n', 'apple\n', 'FOUR\n', '12345\n', ''):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    read_words(path)


if __name__ == '__main__':
    unittest.main()
