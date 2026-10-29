#!/usr/bin/env python3
"""Sanity checks for App/Resources/bible.sqlite (stdlib unittest)."""
import sqlite3, unicodedata, unittest
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "App" / "Resources" / "bible.sqlite"
IDS = ["CUV", "RV1909", "KJV", "ASV", "CUVT", "BSB", "WEB", "BLM"]
NEW_IDS = ["CUVT", "BSB", "WEB", "BLM"]


class BundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

    def q(self, sql, *a):
        return self.db.execute(sql, a).fetchall()

    def test_integrity_and_meta(self):
        self.assertEqual(self.q("PRAGMA integrity_check"), [("ok",)])
        self.assertEqual(self.q("PRAGMA user_version"), [(3,)])
        self.assertEqual(self.q("PRAGMA journal_mode")[0][0].lower(), "delete")
        meta = dict(self.q("SELECT key,value FROM meta"))
        self.assertEqual(meta["schema_version"], "3")
        self.assertIn("OpenBible.info", meta["cross_refs_source"])
        self.assertEqual(meta["structure_source:RV1909"], "BSB (adaptada por versículo)")
        self.assertIn("built_at", meta)

    def test_translations_and_counts(self):
        kjv = set(self.q("SELECT book,chapter,verse FROM verses WHERE translation_id='KJV'"))
        for t in IDS:
            books, n = self.q("SELECT COUNT(DISTINCT book), COUNT(*) FROM verses WHERE translation_id=?", t)[0]
            print(f"{t}: books={books} verses={n}")
            self.assertEqual(books, 66)
            self.assertTrue(31000 <= n <= 31110, (t, n))
            mine = set(self.q("SELECT book,chapter,verse FROM verses WHERE translation_id=?", t))
            print(f"   not in KJV numbering: {len(mine - kjv)}; KJV verses missing here: {len(kjv - mine)}")
        self.assertEqual({r[0] for r in self.q("SELECT id FROM translations")}, set(IDS))
        for (lic,) in self.q("SELECT license FROM translations"):
            self.assertEqual(lic, "Public Domain")
        self.assertEqual(self.q("SELECT has_strongs FROM translations WHERE id='KJV'"), [(1,)])
        self.assertEqual(self.q("SELECT COUNT(*) FROM book_names"), [(198,)])

    def test_john_3_16(self):
        for t in IDS:
            r = self.q("SELECT text FROM verses WHERE translation_id=? AND book=43 AND chapter=3 AND verse=16", t)
            self.assertEqual(len(r), 1, t)
            print(f"{t} Jn 3:16: {r[0][0]}")
        for t, needle in (("CUV", "神爱世人"), ("CUVT", "愛世人")):
            cuv = self.q("SELECT text FROM verses WHERE translation_id=? AND book=43 AND chapter=3 AND verse=16", t)[0][0]
            self.assertIn(needle, cuv)
            self.assertNotIn(" ", cuv)
            self.assertNotIn("　", cuv)
        self.assertIn("one and only Son", self.q("SELECT text FROM verses WHERE translation_id='BSB' AND book=43 AND chapter=3 AND verse=16")[0][0])
        for t in IDS:  # no markup / pilcrows left
            self.assertEqual(self.q("SELECT COUNT(*) FROM verses WHERE translation_id=? AND (text LIKE '%<%' OR text LIKE '%¶%' OR text LIKE '%  %')", t), [(0,)])

    def test_fts(self):
        # trigram: 3+ chars work via MATCH ("得永生"), the bare 2-char "永生" matches nothing.
        r = self.q("SELECT book,chapter,verse FROM verses_fts WHERE verses_fts MATCH '\"得永生\"' AND translation_id='CUV'")
        self.assertGreater(len(r), 5)
        print("MATCH '得永生':", len(r), "| MATCH '永生' (2 chars):",
              len(self.q("SELECT 1 FROM verses_fts WHERE verses_fts MATCH '\"永生\"' AND translation_id='CUV'")))
        r = self.q("SELECT book,chapter,verse FROM verses_fts WHERE verses_fts MATCH 'gracia' AND translation_id='RV1909'")
        self.assertGreater(len(r), 50)
        # NOTE: trigram needs >= 3 chars. 2-char CJK queries (e.g. 永生) return rows only by
        # accident of quoting; the app must fall back to LIKE '%永生%' on verses for 1-2 char queries.
        self.assertGreater(self.q("SELECT COUNT(*) FROM verses WHERE translation_id='CUV' AND text LIKE '%永生%'")[0][0], 10)

    def test_new_translations(self):
        got = {r[0]: r for r in self.q("SELECT id, language, license, has_strongs FROM translations")}
        for t, lang in (("CUVT", "zh"), ("BSB", "en"), ("WEB", "en"), ("BLM", "es")):
            self.assertEqual(got[t][1:], (lang, "Public Domain", 0), t)
            n = self.q("SELECT COUNT(*) FROM verses WHERE translation_id=?", t)[0][0]
            print(f"{t}: {n} verses")
            self.assertTrue(31000 <= n <= 31110, (t, n))
            self.assertGreater(self.q("SELECT COUNT(*) FROM verses_fts WHERE translation_id=?", t)[0][0], 31000)
        self.assertTrue(self.q("SELECT 1 FROM verses_fts WHERE verses_fts MATCH '\"永生\"' AND translation_id='CUVT' LIMIT 1") or
                        self.q("SELECT 1 FROM verses_fts WHERE verses_fts MATCH '\"得永生\"' AND translation_id='CUVT' LIMIT 1"))
        self.assertGreater(len(self.q("SELECT 1 FROM verses_fts WHERE verses_fts MATCH 'loved' AND translation_id='BSB'")), 50)
        # no glued words from dropped footnote markers
        self.assertEqual(self.q("SELECT COUNT(*) FROM verses WHERE translation_id IN ('BSB','WEB','ASV') AND (text LIKE '%onlySon%' OR text LIKE '%man,by%')"), [(0,)])

    def test_cross_refs(self):
        n = self.q("SELECT COUNT(*) FROM cross_refs")[0][0]
        print("cross_refs rows:", n)
        self.assertGreater(n, 300000)
        self.assertEqual(self.q("SELECT COUNT(*) FROM cross_refs WHERE votes < 0"), [(0,)])
        self.assertEqual(self.q("SELECT COUNT(*) FROM cross_refs WHERE to_verse_end < to_verse_start OR book NOT BETWEEN 1 AND 66 OR to_book NOT BETWEEN 1 AND 66"), [(0,)])
        jn = self.q("SELECT to_book,to_chapter,to_verse_start,to_verse_end,votes FROM cross_refs WHERE book=43 AND chapter=3 AND verse=16 ORDER BY votes DESC")
        self.assertGreater(len(jn), 0)
        self.assertEqual(jn[0][:4], (45, 5, 8, 8))                      # Rom 5:8 is the top ref
        self.assertIn((62, 4, 9, 10), {r[:4] for r in jn})              # 1 Jn 4:9-10 (a range)
        plan = self.q("EXPLAIN QUERY PLAN SELECT * FROM cross_refs WHERE book=43 AND chapter=3 AND verse=16")
        self.assertIn("cross_refs_idx", str(plan))

    def test_lexicon(self):
        self.assertEqual(self.q("SELECT lemma FROM lexicon WHERE id='G25'"), [(unicodedata.normalize("NFC", "ἀγαπάω"),)])
        self.assertEqual(self.q("SELECT lemma FROM lexicon WHERE id='H430'"), [(unicodedata.normalize("NFC", "אֱלֹהִים"),)])
        self.assertGreater(self.q("SELECT COUNT(*) FROM lexicon WHERE id LIKE 'G%'")[0][0], 5000)
        self.assertGreater(self.q("SELECT COUNT(*) FROM lexicon WHERE id LIKE 'H%'")[0][0], 8000)

    def test_verse_words(self):
        r = self.q("SELECT strong FROM verse_words WHERE translation_id='KJV' AND book=43 AND chapter=3 AND verse=16 AND word='loved'")
        self.assertEqual(r, [("G25",)])
        self.assertEqual(self.q("SELECT COUNT(*) FROM verse_words WHERE strong LIKE '%G0%' OR strong LIKE 'H0%'"), [(0,)])
        self.assertEqual(self.q("SELECT COUNT(DISTINCT book) FROM verse_words"), [(66,)])
        # every strong number used should exist in the lexicon
        missing = self.q("SELECT DISTINCT strong FROM verse_words WHERE strong IS NOT NULL AND strong NOT IN (SELECT id FROM lexicon)")
        print("strong numbers without lexicon entry:", len(missing), missing[:10])
        self.assertLess(len(missing), 30)
        # Gen 1:1 'God' -> H430
        self.assertTrue(self.q("SELECT 1 FROM verse_words WHERE translation_id='KJV' AND book=1 AND chapter=1 AND verse=1 AND strong='H430'"))

    def test_headings(self):
        self.assertTrue(self.q("SELECT 1 FROM headings WHERE translation_id='CUV' AND book=43 AND chapter=3 AND verse=1"))

    # ---- maquetación (schema 2)
    def test_poetry_psalm_23(self):
        for t in IDS:
            n = self.q("SELECT COUNT(*) FROM layout WHERE translation_id=? AND book=19 AND chapter=23 AND kind='q'", t)[0][0]
            self.assertGreaterEqual(n, 6, t)

    def test_kjv_pilcrow_paragraphs(self):
        # Gén 1:6 y 1:9 abren párrafo (¶ en la KJV)
        for v in (6, 9, 14):
            self.assertEqual(self.q("SELECT kind FROM layout WHERE translation_id='KJV' AND book=1 AND chapter=1 AND verse=? ORDER BY seq LIMIT 1", v), [("p",)])

    def test_john_3_has_paragraphs(self):
        for t in IDS:
            n = self.q("SELECT COUNT(*) FROM layout WHERE translation_id=? AND book=43 AND chapter=3 AND kind IN ('p','m')", t)[0][0]
            self.assertGreater(n, 1, t)

    def test_pieces_concatenate_to_verse_text(self):
        for t in IDS:
            pieces = {}
            for k, tx in self.q("SELECT book||'-'||chapter||'-'||verse, text FROM layout WHERE translation_id=? AND kind!='b' ORDER BY book,chapter,seq", t):
                pieces.setdefault(k, []).append(tx)
            bad = 0
            for k, tx in self.q("SELECT book||'-'||chapter||'-'||verse, text FROM verses WHERE translation_id=?", t):
                if "".join("".join(pieces.get(k, [])).split()) != "".join(tx.split()):
                    bad += 1
            self.assertEqual(bad, 0, t)

    def test_rv1909_no_single_block_chapters(self):
        rows = self.q("""SELECT v.book, v.chapter, COUNT(*) FROM verses v WHERE translation_id='RV1909' GROUP BY v.book, v.chapter
                         HAVING COUNT(*) > 1""")
        single = 0
        for b, c, n in rows:
            blocks = self.q("SELECT COUNT(*) FROM layout WHERE translation_id='RV1909' AND book=? AND chapter=? AND kind NOT IN ('+','b')", b, c)[0][0]
            if blocks <= 1:
                single += 1
        print("RV1909 chapters (>1 verse) with a single block:", single, "of", len(rows))
        self.assertLess(single, len(rows) * 0.05)

    def test_heading_kinds(self):
        self.assertTrue(self.q("SELECT 1 FROM headings WHERE translation_id='CUV' AND book=19 AND chapter=3 AND kind='d'"))
        self.assertTrue(self.q("SELECT 1 FROM headings WHERE translation_id='KJV' AND kind='d'"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
