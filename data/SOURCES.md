# Data sources and licenses

Everything in `App/Resources/bible.sqlite` is built by `data/build_bibles.py` from the sources below.
No data from `/Applications/精读圣经.app` or `~/Library/Containers/cz.jdbible` was used.
License fields were checked on 2026-10-28 against the HelloAO `available_translations.json` metadata
(`license.publicDomain == true`; the build aborts if a translation stops being flagged public domain)
and against the eBible.org catalogue (`https://ebible.org/Scriptures/translations.csv`).

Delivery channel for the eight Bible texts: HelloAO Free Use Bible API
(https://bible.helloao.org/, docs https://bible.helloao.org/docs/), file `/api/{id}/complete.json`
(one request per translation). HelloAO itself is a free-use mirror of eBible.org texts.

## Translations

| DB id | Name | Source | License |
|---|---|---|---|
| CUV | 新标点和合本 (Chinese Union Version, simplified script), HelloAO id `cmn_cu1` | https://ebible.org/Scriptures/details.php?id=cmn-cu89s (via https://bible.helloao.org/api/cmn_cu1/complete.json) | Public Domain. Statement: https://ebible.org/Scriptures/details.php?id=cmn-cu89s ("public domain"). Attribution not required. |
| RV1909 | Santa Biblia - Reina Valera 1909, HelloAO id `spa_r09` | https://ebible.org/Scriptures/details.php?id=spaRV1909 (via https://bible.helloao.org/api/spa_r09/complete.json) | Public Domain. Statement: https://ebible.org/Scriptures/details.php?id=spaRV1909. Attribution not required. |
| KJV | King James (Authorized) Version, 1769 standard text, HelloAO id `eng_kjv` | https://ebible.org/Scriptures/details.php?id=eng-kjv2006 (via https://bible.helloao.org/api/eng_kjv/complete.json) | Public Domain outside the UK. Statement: https://ebible.org/Scriptures/details.php?id=eng-kjv2006 (copyright page `copr.htm` inside the USFM zip). **UK caveat:** Crown letters patent (Cambridge/Oxford University Presses, Collins) restrict *printing/importing printed copies* in the United Kingdom; this does not affect other jurisdictions. A UK App Store release of a digital app is generally not "printing", but get a legal opinion if the UK is a target market. |
| ASV | American Standard Version (1901), HelloAO id `eng_asv` | https://ebible.org/Scriptures/details.php?id=eng-asv (via https://bible.helloao.org/api/eng_asv/complete.json) | Public Domain. Statement: https://ebible.org/Scriptures/details.php?id=eng-asv. Attribution not required. |

| CUVT | 新標點和合本 (Chinese Union Version, traditional script), HelloAO id `cmn_cuv` | https://ebible.org/Scriptures/details.php?id=cmn-cu89t (via https://bible.helloao.org/api/cmn_cuv/complete.json) | Public Domain (HelloAO `publicDomain: true`; eBible.org statement at the source URL). Attribution not required. Added in schema 3. |
| BSB | Berean Standard Bible, HelloAO id `BSB` | https://berean.bible/ (via https://bible.helloao.org/api/BSB/complete.json) | Public Domain. HelloAO's metadata has **no license block** for BSB, so the build uses a manually verified override: "The Berean Bible ... texts are officially dedicated to the public domain as of April 30, 2023. All uses are freely permitted." (https://berean.bible/terms.htm, read 2026-10-29). Attribution appreciated, not required. Added in schema 3. |
| WEB | World English Bible (Protestant canon, `ENGWEBP`; includes no deuterocanon) | https://ebible.org/Scriptures/details.php?id=engwebp (via https://bible.helloao.org/api/ENGWEBP/complete.json) | Public Domain (HelloAO `publicDomain: true`). Attribution not required ("World English Bible" is a trademark of Michael Paul Johnson/eBible.org; the name is used here only to identify the text). Added in schema 3. |
| BLM | Santa Biblia libre para el mundo (Spanish Free Bible for the World), HelloAO id `spa_blm`; only the 66 canonical books are imported (deuterocanonical books skipped) | https://ebible.org/Scriptures/details.php?id=spablm (via https://bible.helloao.org/api/spa_blm/complete.json) | Public Domain (HelloAO `publicDomain: true`). Attribution not required. Added in schema 3. |

Spanish candidates checked (HelloAO `available_translations.json`, 2026-10-29): `spa_blm` Libre para el mundo (PD, **used**), `spa_bll` Libre Latinoamericano (PD, same family, not added), `spa_bes` Español Sencillo 2026 (PD, simplified paraphrase-like register, not added), `spa_r09` RV1909 (PD, already in), `spa_onbv` Nueva Biblia Viva (attribution required + copyleft, rejected), `spa_pdt` Palabra de Dios para ti (attribution required, not public domain, rejected), `spa_vbl` Versión Biblia Libre (copyleft/attribution, rejected), `spa_rvg` Reina Valera Gómez and `spa_v2p` Valera 1602 Purificada (no license block at all, rejected).
Chinese rejected: `cmn_cuvmps`/`cmn_cuvmpt`/`cmn_csbs`/`cmn_csbt` (CC BY-NC-ND), `cmn_cbs`/`cmn_cbt`/`cmn_feb` (attribution + copyleft, not added).

Text clean-up applied to all HelloAO texts at build time: footnote markers are dropped and the word space they swallow in some sources ("only" + note + "Son") is restored; consecutive poetry lines without a line break get a space between them. (This also fixed 32 ASV verses where two sentences were glued.)

Notes
* CUV: the HelloAO sibling `cmn_cuvmps` (现代标点和合本) is **not** used: it is flagged CC BY-NC-ND 4.0 (non-commercial, no derivatives). `cmn_cu1` is the 1919 Union Version text with the 1989 "new punctuation" edition as published by eBible.org, which declares it public domain.
  If you want a belt-and-braces position, note that the copyright status of the 1989 punctuation layer rests on eBible.org's declaration.
* Courtesy credit (not legally required): "Texts courtesy of eBible.org and the HelloAO Free Use Bible API."

## Strong's-tagged KJV (`verse_words`, translation `KJV`)

* Source: eBible.org `eng-kjv2006` USFM with `\w word|strong="G0025"\w*` markup,
  https://ebible.org/Scriptures/eng-kjv2006_usfm.zip (catalogue entry: "The King James Version ... using the standardized text of 1769, protocanon only, with Strong's numbers added").
* License: Public Domain (https://ebible.org/Scriptures/details.php?id=eng-kjv2006 (copyright page `copr.htm` inside the USFM zip); same UK letters-patent caveat as above). Credit line on that page: "courtesy of the Crosswire Bible Society and eBible.org".
* Strong numbers are stored without leading zeros (`G25`, `H430`). Words not tagged in the source get `strong = NULL`. Multi-word tagged phrases (e.g. "only begotten" = G3439) are one `verse_words` row. Punctuation is stripped from word tokens.

## Lexicon (`lexicon`)

* Source: OpenScriptures Strong's dictionaries, https://github.com/openscriptures/strongs
  * Greek: `greek/StrongsGreekDictionaryXML_1.4.zip` (Ulrik Petersen's XML of Strong's 1890 dictionary). Header: "Public Domain -- Copy Freely".
  * Hebrew: `hebrew/StrongHebrewG.xml` (OSIS XML; David Troidl / David Instone-Brewer edition of Strong's 1894 dictionary). Work metadata `<rights>Public Domain</rights>`.
* License: Public Domain (original works by James Strong, 1890/1894).
* **Not used:** the `*-dictionary.js` JSON files in the same repo; their header says "Copyright Open Scriptures. CC-BY-SA" for the JSON packaging, so the XML (PD-marked) files were used instead.
* Field mapping: `lemma` = original-script lemma, `translit` = transliteration, `pronunciation` = Strong's pronunciation guide, `definition` = Strong's definition, `kjv_usage` = KJV rendering list.
* Suggested credit (optional): "Strong's Hebrew and Greek dictionaries, public domain, via OpenScriptures."

## Book names

Names and abbreviations are factual data (English, Spanish, Chinese); the Chinese and Spanish names were taken from the project's own book table in `/Users/jiaheqiu/mcp/jingdu-bible-mcp/server.py` (not from any copyrighted Bible data), abbreviations chosen as common standard forms.

## Estructura del texto (tabla `layout`, schema_version 2)

* **CUV, KJV, ASV**: párrafos, poesía (`q` por nivel), saltos de estrofa (`b`) y `¶` (KJV) salen del JSON de HelloAO (`line_break`, `poem`, `lineBreak`, `hebrew_subtitle` -> título `d`).
* **RV1909**: ninguna fuente libre trae estructura. Se toma prestada de la **Berean Standard Bible** (USFM de eBible.org, `https://eBible.org/Scriptures/engbsb_usfm.zip`, dominio público: https://berean.bible/terms.htm) y se aplica por versículos enteros (un corte en mitad de un versículo se mueve al siguiente; versículos ausentes en la plantilla = prosa continua). No se copian títulos `\s` ni `\d`. En `meta`: `structure_source:RV1909 = 'BSB (adaptada por versículo)'`.
* Fuera de alcance: Strong en español desde el USFM de RV1909; palabras de Jesús en rojo (`wordsOfJesus`).

## Referencias cruzadas (`cross_refs`, schema_version 3)

* Source: **OpenBible.info Cross References**, https://www.openbible.info/labs/cross-references/ , data file https://a.openbible.info/data/cross-references.zip (`cross_references.txt`, 344,799 rows: `From Verse<TAB>To Verse<TAB>Votes`).
* License: **Creative Commons Attribution (CC BY)**. The page says "Unless otherwise indicated, all content is licensed under a Creative Commons Attribution License" (link http://creativecommons.org/licenses/by/4.0/); the data file header reads `#www.openbible.info CC-BY 2026-10-26`. No NC/ND. The build aborts if the page stops linking to the CC BY licence or the file header changes. The data is "primarily from public-domain sources, especially the Treasury of Scripture Knowledge" plus the author's Topical Bible and Twitter Bible Search seed votes, and community votes. Treasury of Scripture Knowledge alone was not chosen because OpenBible already incorporates it and adds relevance votes (needed for ordering).
* **Required attribution** (shown in the About window): "Cross references: OpenBible.info, licensed under Creative Commons Attribution (CC BY 4.0), https://www.openbible.info/labs/cross-references/ . Derived mainly from the Treasury of Scripture Knowledge (public domain)." The scripture quotations on the OpenBible page itself (ESV) are not part of the data file and are not used.
* Processing: OSIS-like book codes mapped to 1-66; 1,231 rows with negative votes dropped (343,568 kept); target ranges kept (`to_verse_start`..`to_verse_end`); the 655 ranges that cross a chapter boundary are clamped to the last verse of their first chapter (the schema has a single `to_chapter`, last verse taken from the KJV table). Versification follows the source (KJV/ESV style), like the KJV table; other translations with different numbering simply may not have a matching verse.
