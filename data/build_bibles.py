#!/usr/bin/env python3
"""Build App/Resources/bible.sqlite from public-domain / openly licensed sources.

Standard library only. Downloads go to data/cache/ (skipped when already cached),
sequentially, with a User-Agent, a 0.3-1 s pause between requests and retry with
backoff on 429/5xx. See data/SOURCES.md for licenses.
"""
import json, os, random, re, sqlite3, sys, time, unicodedata, urllib.request, urllib.error
import zipfile, xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache"
OUT = HERE.parent / "App" / "Resources" / "bible.sqlite"
UA = "biblia-app-databuild/1.0 (clean-room Bible study app; public-domain texts only; contact jiahe44@gmail.com)"
HELLOAO = "https://bible.helloao.org/api"
OS_RAW = "https://raw.githubusercontent.com/openscriptures/strongs/master"
KJV_USFM_URL = "https://ebible.org/Scriptures/eng-kjv2006_usfm.zip"

REQUESTS_MADE = 0

# (number, English, English abbrev, Spanish, Spanish abbrev, Chinese full, Chinese short)
BOOKS = [
    (1, 'Genesis', 'Gen', 'Génesis', 'Gn', '创世记', '创'),
    (2, 'Exodus', 'Exod', 'Éxodo', 'Éx', '出埃及记', '出'),
    (3, 'Leviticus', 'Lev', 'Levítico', 'Lv', '利未记', '利'),
    (4, 'Numbers', 'Num', 'Números', 'Nm', '民数记', '民'),
    (5, 'Deuteronomy', 'Deut', 'Deuteronomio', 'Dt', '申命记', '申'),
    (6, 'Joshua', 'Josh', 'Josué', 'Jos', '约书亚记', '书'),
    (7, 'Judges', 'Judg', 'Jueces', 'Jue', '士师记', '士'),
    (8, 'Ruth', 'Ruth', 'Rut', 'Rt', '路得记', '得'),
    (9, '1 Samuel', '1 Sam', '1 Samuel', '1 S', '撒母耳记上', '撒上'),
    (10, '2 Samuel', '2 Sam', '2 Samuel', '2 S', '撒母耳记下', '撒下'),
    (11, '1 Kings', '1 Kgs', '1 Reyes', '1 R', '列王纪上', '王上'),
    (12, '2 Kings', '2 Kgs', '2 Reyes', '2 R', '列王纪下', '王下'),
    (13, '1 Chronicles', '1 Chr', '1 Crónicas', '1 Cr', '历代志上', '代上'),
    (14, '2 Chronicles', '2 Chr', '2 Crónicas', '2 Cr', '历代志下', '代下'),
    (15, 'Ezra', 'Ezra', 'Esdras', 'Esd', '以斯拉记', '拉'),
    (16, 'Nehemiah', 'Neh', 'Nehemías', 'Neh', '尼希米记', '尼'),
    (17, 'Esther', 'Esth', 'Ester', 'Est', '以斯帖记', '斯'),
    (18, 'Job', 'Job', 'Job', 'Job', '约伯记', '伯'),
    (19, 'Psalms', 'Ps', 'Salmos', 'Sal', '诗篇', '诗'),
    (20, 'Proverbs', 'Prov', 'Proverbios', 'Pr', '箴言', '箴'),
    (21, 'Ecclesiastes', 'Eccl', 'Eclesiastés', 'Ec', '传道书', '传'),
    (22, 'Song of Songs', 'Song', 'Cantares', 'Cnt', '雅歌', '歌'),
    (23, 'Isaiah', 'Isa', 'Isaías', 'Is', '以赛亚书', '赛'),
    (24, 'Jeremiah', 'Jer', 'Jeremías', 'Jer', '耶利米书', '耶'),
    (25, 'Lamentations', 'Lam', 'Lamentaciones', 'Lm', '耶利米哀歌', '哀'),
    (26, 'Ezekiel', 'Ezek', 'Ezequiel', 'Ez', '以西结书', '结'),
    (27, 'Daniel', 'Dan', 'Daniel', 'Dn', '但以理书', '但'),
    (28, 'Hosea', 'Hos', 'Oseas', 'Os', '何西阿书', '何'),
    (29, 'Joel', 'Joel', 'Joel', 'Jl', '约珥书', '珥'),
    (30, 'Amos', 'Amos', 'Amós', 'Am', '阿摩司书', '摩'),
    (31, 'Obadiah', 'Obad', 'Abdías', 'Abd', '俄巴底亚书', '俄'),
    (32, 'Jonah', 'Jonah', 'Jonás', 'Jon', '约拿书', '拿'),
    (33, 'Micah', 'Mic', 'Miqueas', 'Mi', '弥迦书', '弥'),
    (34, 'Nahum', 'Nah', 'Nahúm', 'Nah', '那鸿书', '鸿'),
    (35, 'Habakkuk', 'Hab', 'Habacuc', 'Hab', '哈巴谷书', '哈'),
    (36, 'Zephaniah', 'Zeph', 'Sofonías', 'Sof', '西番雅书', '番'),
    (37, 'Haggai', 'Hag', 'Hageo', 'Hag', '哈该书', '该'),
    (38, 'Zechariah', 'Zech', 'Zacarías', 'Zac', '撒迦利亚书', '亚'),
    (39, 'Malachi', 'Mal', 'Malaquías', 'Mal', '玛拉基书', '玛'),
    (40, 'Matthew', 'Matt', 'Mateo', 'Mt', '马太福音', '太'),
    (41, 'Mark', 'Mark', 'Marcos', 'Mr', '马可福音', '可'),
    (42, 'Luke', 'Luke', 'Lucas', 'Lc', '路加福音', '路'),
    (43, 'John', 'John', 'Juan', 'Jn', '约翰福音', '约'),
    (44, 'Acts', 'Acts', 'Hechos', 'Hch', '使徒行传', '徒'),
    (45, 'Romans', 'Rom', 'Romanos', 'Ro', '罗马书', '罗'),
    (46, '1 Corinthians', '1 Cor', '1 Corintios', '1 Co', '哥林多前书', '林前'),
    (47, '2 Corinthians', '2 Cor', '2 Corintios', '2 Co', '哥林多后书', '林后'),
    (48, 'Galatians', 'Gal', 'Gálatas', 'Gá', '加拉太书', '加'),
    (49, 'Ephesians', 'Eph', 'Efesios', 'Ef', '以弗所书', '弗'),
    (50, 'Philippians', 'Phil', 'Filipenses', 'Flp', '腓立比书', '腓'),
    (51, 'Colossians', 'Col', 'Colosenses', 'Col', '歌罗西书', '西'),
    (52, '1 Thessalonians', '1 Thess', '1 Tesalonicenses', '1 Ts', '帖撒罗尼迦前书', '帖前'),
    (53, '2 Thessalonians', '2 Thess', '2 Tesalonicenses', '2 Ts', '帖撒罗尼迦后书', '帖后'),
    (54, '1 Timothy', '1 Tim', '1 Timoteo', '1 Ti', '提摩太前书', '提前'),
    (55, '2 Timothy', '2 Tim', '2 Timoteo', '2 Ti', '提摩太后书', '提后'),
    (56, 'Titus', 'Titus', 'Tito', 'Tit', '提多书', '多'),
    (57, 'Philemon', 'Phlm', 'Filemón', 'Flm', '腓利门书', '门'),
    (58, 'Hebrews', 'Heb', 'Hebreos', 'He', '希伯来书', '来'),
    (59, 'James', 'Jas', 'Santiago', 'Stg', '雅各书', '雅'),
    (60, '1 Peter', '1 Pet', '1 Pedro', '1 P', '彼得前书', '彼前'),
    (61, '2 Peter', '2 Pet', '2 Pedro', '2 P', '彼得后书', '彼后'),
    (62, '1 John', '1 John', '1 Juan', '1 Jn', '约翰一书', '约壹'),
    (63, '2 John', '2 John', '2 Juan', '2 Jn', '约翰二书', '约贰'),
    (64, '3 John', '3 John', '3 Juan', '3 Jn', '约翰三书', '约叁'),
    (65, 'Jude', 'Jude', 'Judas', 'Jud', '犹大书', '犹'),
    (66, 'Revelation', 'Rev', 'Apocalipsis', 'Ap', '启示录', '启'),
]

# translation_id -> (HelloAO id, display name, language, license text, source page)
TRANSLATIONS = {
    "CUV": ("cmn_cu1", "和合本 (新标点和合本, 简体) Chinese Union Version", "zh"),
    "RV1909": ("spa_r09", "Reina-Valera 1909", "es"),
    "KJV": ("eng_kjv", "King James Version (1769 text)", "en"),
    "ASV": ("eng_asv", "American Standard Version (1901)", "en"),
}


def fetch(url, name):
    """Download url into cache/name unless cached. Polite + retry. Returns Path."""
    global REQUESTS_MADE
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / name
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    delay = 2.0
    for attempt in range(6):
        time.sleep(random.uniform(0.3, 1.0))
        REQUESTS_MADE += 1
        print(f"GET {url}", flush=True)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            tmp = dest.with_suffix(dest.suffix + ".part")
            tmp.write_bytes(data)
            tmp.rename(dest)
            return dest
        except urllib.error.HTTPError as e:
            if e.code == 429 or e.code >= 500:
                ra = e.headers.get("Retry-After")
                wait = float(ra) if ra and ra.isdigit() else delay
                print(f"  HTTP {e.code}, retrying in {wait:.0f}s", flush=True)
                time.sleep(wait); delay *= 2
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  network error {e}, retrying in {delay:.0f}s", flush=True)
            time.sleep(delay); delay *= 2
    raise RuntimeError(f"failed to download {url}")


def norm(s):
    s = unicodedata.normalize("NFC", s.replace("\u00b6", " "))  # drop pilcrow paragraph marks
    return re.sub(r"\s+", " ", s).strip()


CJK_RE = re.compile(r"[^\x00-\x7f]")


def norm_zh(s):
    s = norm(s.replace("\u3000", " "))
    # drop spaces adjacent to any non-ASCII char (honorific space before 神, etc.)
    s = re.sub(r"\s+(?=[^\x00-\x7f])", "", s)
    s = re.sub(r"(?<=[^\x00-\x7f])\s+", "", s)
    return s


def flatten(items):
    """HelloAO verse content -> plain text (drops footnote refs, joins poetry lines)."""
    out = []
    for x in items:
        if isinstance(x, str):
            out.append(x)
        elif isinstance(x, dict):
            if "text" in x:
                out.append(x["text"])
            elif x.get("lineBreak"):
                out.append(" ")
            # noteId (footnote marker) and anything else: dropped
    return "".join(out)


def parse_chapter_layout(content, lang):
    """HelloAO chapter content -> (verses, headings, pieces).

    verses:  [(number, text)]            plain text, one line (unchanged vs schema 1)
    headings:[(verse, text, kind)]       kind 's1' (heading) | 'd' (hebrew_subtitle)
    pieces:  [(kind, level, verse, text)] kind = block kind opening a block, or '+' (continuation)
    """
    nz = norm_zh if lang == "zh" else norm
    verses, headings, pieces = [], [], []
    pending = []
    # estado de maquetación
    need_new = True        # el próximo trozo abre bloque
    pending_para = True    # ... y ese bloque es un párrafo (p) en vez de continuación (m)
    last_kind = None       # tipo del último bloque abierto

    def emit(kind_if_new, level, verse, text, poetic):
        nonlocal need_new, pending_para, last_kind
        text = nz(text)
        if not text:
            return
        open_new = need_new or last_kind is None or (poetic != (last_kind in ("q", "qr"))) \
            or (poetic and level != cur_level[0])
        if open_new:
            if poetic:
                k = kind_if_new
            elif last_kind in ("q", "qr", "li") and not pending_para:
                k = "m"
            else:
                k = "p"
            pieces.append((k, level, verse, text))
            last_kind = k
            cur_level[0] = level
        else:
            pieces.append(("+", level, verse, text))
        need_new = False
        pending_para = False

    cur_level = [1]
    for it in content:
        t = it["type"]
        if t in ("heading", "hebrew_subtitle"):
            pending.append((flatten(it["content"]), "s1" if t == "heading" else "d"))
            need_new = True; pending_para = True
        elif t == "line_break":
            if last_kind in ("q", "qr", "li") and pieces and pieces[-1][0] != "b":
                pieces.append(("b", 1, pieces[-1][2], ""))
            need_new = True; pending_para = True
        elif t == "verse":
            n = it["number"]
            text = nz(flatten(it["content"]))
            if not text:
                pending = []
                continue
            for h, k in pending:
                h = nz(h)
                if h:
                    headings.append((n, h, k))
            pending = []
            verses.append((n, text))
            first = True
            for x in it["content"]:
                if isinstance(x, str):
                    # ¶ abre párrafo (gana sobre line_break: mismo efecto)
                    segs = x.split("\u00b6")
                    for i, seg in enumerate(segs):
                        if i > 0:
                            need_new = True; pending_para = True
                        if seg.strip():
                            if first and last_kind in ("q", "qr"):
                                pass
                            emit("p", 1, n, seg, False)
                            first = False
                elif isinstance(x, dict):
                    if "text" in x:
                        poem = x.get("poem")
                        if poem:
                            if first:
                                need_new = True   # un versículo poético empieza línea nueva
                            emit("q", int(poem), n, x["text"], True)
                        else:
                            emit("p", 1, n, x["text"], False)
                        first = False
                    elif x.get("lineBreak"):
                        need_new = True
                        if last_kind not in ("q", "qr", "li"):
                            pending_para = True
    return verses, headings, pieces


def load_helloao(tid, lang):
    hid = TRANSLATIONS[tid][0]
    path = fetch(f"{HELLOAO}/{hid}/complete.json", f"{hid}.complete.json")
    d = json.loads(path.read_text(encoding="utf-8"))
    verses, headings, layout = [], [], []
    for b in d["books"]:
        bn = b["order"]
        assert 1 <= bn <= 66, (hid, b["id"], bn)
        for ch in b["chapters"]:
            cn = ch["chapter"]["number"]
            vs, hs, ps = parse_chapter_layout(ch["chapter"]["content"], lang)
            verses += [(tid, bn, cn, n, t) for n, t in vs]
            headings += [(tid, bn, cn, n, t, k) for n, t, k in hs]
            layout += [(tid, bn, cn, i + 1, k, lvl, v, t) for i, (k, lvl, v, t) in enumerate(ps)]
    return verses, headings, layout


# ---------------------------------------------------------------- BSB structure template (for RV1909)
BSB_URL = "https://eBible.org/Scriptures/engbsb_usfm.zip"
BLOCK_MARK = re.compile(r"^\\(p|m|pmo|pm|pi\d?|mi|nb|q\d?|qr|qc|qm\d?|li\d?|lim\d?|b)(?:\s|$)")


def load_bsb_template():
    """(book, chapter, verse) -> (kind, level, blank_before) para versículos que ABREN bloque.

    Un versículo abre bloque si un marcador de bloque (\\m, \\p, \\q1, \\li1...) aparece desde
    el versículo anterior hasta él. Marcadores en mitad de un versículo se aplican al
    versículo siguiente (los versículos no se parten). Títulos \\s y \\d no se copian.
    """
    zpath = fetch(BSB_URL, "engbsb_usfm.zip")
    tmpl = {}
    with zipfile.ZipFile(zpath) as z:
        files = {}
        for n in z.namelist():
            m = re.match(r"\d+-([0-9A-Z]{3})engbsb\.usfm$", n)
            if m:
                files[m.group(1)] = n
        for bn, code in enumerate(USFM_CODES, 1):
            chap = 0
            marker = None; blank = False
            for line in z.read(files[code]).decode("utf-8").splitlines():
                line = line.rstrip()
                m = re.match(r"\\c (\d+)", line)
                if m:
                    chap = int(m.group(1)); marker = None; blank = False
                    continue
                bm = BLOCK_MARK.match(line)
                if bm:
                    mk = bm.group(1)
                    if mk == "b":
                        blank = True
                    else:
                        marker = mk
                vm = re.search(r"\\v (\d+)", line)
                if vm and chap:
                    v = int(vm.group(1))
                    if marker:
                        mk = marker
                        if mk.startswith("q"):
                            k, lvl = ("qr", 1) if mk == "qr" else ("q", int(mk[1:] or 1))
                        elif mk.startswith("li"):
                            k, lvl = "li", int(re.sub(r"\D", "", mk) or 1)
                        elif mk == "pmo":
                            k, lvl = "pmo", 1
                        elif mk == "m" or mk == "nb":
                            k, lvl = "m", 1
                        else:
                            k, lvl = "p", 1
                        tmpl[(bn, chap, v)] = (k, lvl, blank)
                    marker = None; blank = False
                    # un marcador en la MISMA línea tras \v (p. ej. "\\v 5 ... \\q2") se trata como mitad de versículo
    return tmpl


def layout_from_template(tid, verses, tmpl):
    """RV1909: aplica la plantilla por versículos enteros. verses = [(tid,b,c,v,text)]."""
    layout = []
    seq = {}
    last = {}
    for (_, b, c, v, text) in verses:
        key = (b, c)
        seq[key] = seq.get(key, 0)
        t = tmpl.get((b, c, v))
        prev = last.get(key)
        rows = []
        if t is None:
            kind = "+" if prev else "p"
            lvl = 1
        else:
            kind, lvl, blank = t
            if prev is None and kind == "m":
                kind = "p"
            if blank and prev in ("q", "qr", "li"):
                rows.append(("b", 1, v, ""))
        rows.append((kind, lvl, v, text))
        for (k, l, vv, tx) in rows:
            seq[key] += 1
            layout.append((tid, b, c, seq[key], k, l, vv, tx))
        if kind != "+":
            last[key] = kind
        elif key not in last:
            last[key] = "p"
    return layout


# ---------------------------------------------------------------- KJV + Strong's
USFM_CODES = ("GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM "
              "EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP "
              "COL 1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV").split()
SKIP_MARKERS = {"id", "h", "toc1", "toc2", "toc3", "mt", "mt1", "mt2", "mt3", "ms", "ms1", "mr", "s", "s1", "s2",
                "r", "d", "sp", "cl", "cp", "ca", "va", "vp", "rem", "ide", "usfm", "c", "mte", "imt", "is", "ip"}
W_RE = re.compile(r'\\\+?w ([^|\\]*)\|strong="([GH]\d+)"\\\+?w\*')
MARK_RE = re.compile(r"\\\+?[a-z0-9]+\*?")
PUNCT_EDGE = re.compile(r"^[^\w]+|[^\w]+$")


def clean_word(w):
    return PUNCT_EDGE.sub("", w.replace("’", "'")).replace("'", "’") if w else w


def parse_usfm_verse(text):
    """-> list of (word, strong|None)."""
    text = re.sub(r"\\f .*?\\f\*", "", text)
    text = re.sub(r"\\x .*?\\x\*", "", text)
    words, pos = [], 0

    def plain(seg):
        seg = MARK_RE.sub(" ", seg).replace("¶", " ")
        for tok in seg.split():
            tok = PUNCT_EDGE.sub("", tok)
            if tok:
                words.append((tok, None))

    for m in W_RE.finditer(text):
        plain(text[pos:m.start()])
        w = norm(MARK_RE.sub(" ", m.group(1)))
        w = PUNCT_EDGE.sub("", w)
        s = m.group(2)
        s = s[0] + str(int(s[1:]))
        if w:
            words.append((w, s))
        pos = m.end()
    plain(text[pos:])
    return words


def load_kjv_words():
    zpath = fetch(KJV_USFM_URL, "eng-kjv2006_usfm.zip")
    out = []
    with zipfile.ZipFile(zpath) as z:
        files = {}
        for n in z.namelist():
            m = re.match(r"\d+-([0-9A-Z]{3})eng-kjv2006\.usfm$", n)
            if m:
                files[m.group(1)] = n
        for bn, code in enumerate(USFM_CODES, 1):
            raw = z.read(files[code]).decode("utf-8")
            chap, verse, buf = 0, None, []
            vmap = {}

            def flush():
                if verse is not None:
                    vmap.setdefault((chap, verse), []).extend(buf)

            for line in raw.splitlines():
                line = line.rstrip()
                m = re.match(r"\\([a-z0-9]+)\*?\s?(.*)$", line)
                if not m:
                    if verse is not None:
                        buf.append(line)
                    continue
                mk, rest = m.group(1), m.group(2)
                if mk == "c":
                    flush(); verse = None; buf = []
                    chap = int(rest.split()[0])
                elif mk == "v":
                    flush(); buf = []
                    vm = re.match(r"(\d+)(?:-\d+)?\s*(.*)$", rest)
                    verse = int(vm.group(1)); buf.append(vm.group(2))
                elif mk in SKIP_MARKERS:
                    continue
                elif verse is not None:
                    buf.append(line)   # paragraph/poetry markers get stripped later
            flush()
            for (c, v), parts in sorted(vmap.items()):
                for i, (w, s) in enumerate(parse_usfm_verse(" ".join(parts)), 1):
                    out.append(("KJV", bn, c, v, i, w, s))
    return out


# ---------------------------------------------------------------- Lexicon
def gtext(el):
    """Text of an element; <greek> -> unicode, <strongsref> -> G123/H123."""
    parts = [el.text or ""]
    for ch in el:
        if ch.tag == "greek":
            parts.append(ch.get("unicode", ""))
        elif ch.tag == "strongsref":
            parts.append(("G" if ch.get("language") == "GREEK" else "H") + str(int(ch.get("strongs"))))
        elif ch.tag == "pronunciation":
            pass
        else:
            parts.append(gtext(ch))
        parts.append(ch.tail or "")
    return "".join(parts)


def load_lexicon():
    rows = {}
    gz = fetch(f"{OS_RAW}/greek/StrongsGreekDictionaryXML_1.4.zip", "StrongsGreekDictionaryXML_1.4.zip")
    with zipfile.ZipFile(gz) as z:
        root = ET.fromstring(z.read("strongsgreek.xml"))
    for e in root.iter("entry"):
        num = int(e.get("strongs"))
        g = e.find("greek"); p = e.find("pronunciation")
        sd = e.find("strongs_def"); kd = e.find("kjv_def")
        kjv = norm(gtext(kd)) if kd is not None else ""
        kjv = re.sub(r"^:--\s*", "", kjv)
        rows[f"G{num}"] = (f"G{num}", g.get("unicode") if g is not None else None,
                           g.get("translit") if g is not None else None,
                           p.get("strongs") if p is not None else None,
                           norm(gtext(sd)) if sd is not None else None, kjv or None)
    hp = fetch(f"{OS_RAW}/hebrew/StrongHebrewG.xml", "StrongHebrewG.xml")
    ns = "{http://www.bibletechnologies.net/2003/OSIS/namespace}"
    root = ET.parse(hp).getroot()
    for e in root.iter(ns + "div"):
        if e.get("type") != "entry":
            continue
        w = e.find(ns + "w")
        if w is None or not (w.get("ID") or "").startswith("H"):
            continue
        sid = "H" + str(int(w.get("ID")[1:].rstrip("abcdefghijklmnopqrstuvwxyz") or 0))
        expl = tr = None
        for n in e.findall(ns + "note"):
            if n.get("type") == "explanation":
                expl = norm("".join(n.itertext()))
            elif n.get("type") == "translation":
                tr = norm("".join(n.itertext()))
        rows[sid] = (sid, w.get("lemma"), w.get("xlit"), w.get("POS"), expl, tr)
    nf = lambda v: unicodedata.normalize("NFC", v) if v else v
    return [tuple(nf(v) for v in r) for r in rows.values()]


# ---------------------------------------------------------------- DB
SCHEMA = """
CREATE TABLE translations(id TEXT PRIMARY KEY, name TEXT NOT NULL, language TEXT NOT NULL,
  license TEXT NOT NULL, source_url TEXT NOT NULL, has_strongs INTEGER NOT NULL DEFAULT 0);
CREATE TABLE book_names(book INTEGER NOT NULL, language TEXT NOT NULL, name TEXT NOT NULL, abbrev TEXT NOT NULL,
  PRIMARY KEY(book, language));
CREATE TABLE verses(translation_id TEXT NOT NULL, book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  text TEXT NOT NULL, PRIMARY KEY(translation_id, book, chapter, verse)) WITHOUT ROWID;
CREATE VIRTUAL TABLE verses_fts USING fts5(text, translation_id UNINDEXED, book UNINDEXED, chapter UNINDEXED, verse UNINDEXED, tokenize='trigram');
CREATE TABLE headings(translation_id TEXT NOT NULL, book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  text TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 's1');
CREATE TABLE layout(translation_id TEXT NOT NULL, book INTEGER NOT NULL, chapter INTEGER NOT NULL,
  seq INTEGER NOT NULL, kind TEXT NOT NULL, level INTEGER NOT NULL DEFAULT 1, verse INTEGER NOT NULL, text TEXT NOT NULL,
  PRIMARY KEY(translation_id, book, chapter, seq)) WITHOUT ROWID;
CREATE INDEX headings_idx ON headings(translation_id, book, chapter);
CREATE TABLE verse_words(translation_id TEXT NOT NULL, book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
  idx INTEGER NOT NULL, word TEXT NOT NULL, strong TEXT, PRIMARY KEY(translation_id, book, chapter, verse, idx)) WITHOUT ROWID;
CREATE INDEX verse_words_strong ON verse_words(strong);
CREATE TABLE lexicon(id TEXT PRIMARY KEY, lemma TEXT, translit TEXT, pronunciation TEXT, definition TEXT, kjv_usage TEXT);
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
"""


def license_text(info):
    lic = info["license"]
    if lic.get("publicDomain"):
        return "Public Domain"
    raise RuntimeError(f"{info['id']} is not public domain: {lic}")


def main():
    avail = json.loads(fetch(f"{HELLOAO}/available_translations.json", "available_translations.json")
                       .read_text(encoding="utf-8"))
    info = {t["id"]: t for t in avail["translations"]}

    if OUT.exists():
        OUT.unlink()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(OUT)
    db.execute("PRAGMA journal_mode=DELETE")
    db.executescript(SCHEMA)

    for tid, (hid, name, lang) in TRANSLATIONS.items():
        t = info[hid]
        lic = license_text(t)  # aborts the build if a source is not public domain
        src = t.get("website") or t.get("licenseUrl")
        db.execute("INSERT INTO translations VALUES(?,?,?,?,?,?)",
                   (tid, name, lang, lic, src, 1 if tid == "KJV" else 0))
    for n, en, ena, es, esa, zf, zs in BOOKS:
        db.executemany("INSERT INTO book_names VALUES(?,?,?,?)",
                       [(n, "en", en, ena), (n, "es", es, esa), (n, "zh", zf, zs)])

    bsb = None
    for tid, (hid, name, lang) in TRANSLATIONS.items():
        verses, headings, layout = load_helloao(tid, lang)
        db.executemany("INSERT INTO verses VALUES(?,?,?,?,?)", verses)
        db.executemany("INSERT INTO verses_fts(text,translation_id,book,chapter,verse) VALUES(?,?,?,?,?)",
                       [(v[4], v[0], v[1], v[2], v[3]) for v in verses])
        if tid == "RV1909":
            if bsb is None:
                bsb = load_bsb_template()
            layout = layout_from_template(tid, verses, bsb)
        db.executemany("INSERT INTO headings VALUES(?,?,?,?,?,?)", headings)
        db.executemany("INSERT INTO layout VALUES(?,?,?,?,?,?,?,?)", layout)
        print(f"{tid}: {len(verses)} verses, {len(headings)} headings, {len(layout)} layout rows")

    words = load_kjv_words()
    db.executemany("INSERT INTO verse_words VALUES(?,?,?,?,?,?,?)", words)
    print(f"KJV words: {len(words)}")

    lex = load_lexicon()
    db.executemany("INSERT INTO lexicon VALUES(?,?,?,?,?,?)", lex)
    print(f"lexicon: {len(lex)}")

    db.execute("INSERT INTO meta VALUES('schema_version','2')")
    db.execute("INSERT INTO meta VALUES('structure_source:RV1909','BSB (adaptada por versículo)')")
    db.execute("INSERT INTO meta VALUES('built_at',?)", (datetime.now(timezone.utc).isoformat(timespec="seconds"),))
    db.commit()
    db.execute("INSERT INTO verses_fts(verses_fts) VALUES('optimize')")
    db.commit()
    db.execute("PRAGMA user_version=2")
    db.execute("VACUUM")
    db.close()
    print(f"wrote {OUT} ({OUT.stat().st_size/1e6:.1f} MB); HTTP requests this run: {REQUESTS_MADE}")


if __name__ == "__main__":
    main()
