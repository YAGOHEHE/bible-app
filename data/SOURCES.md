# Data sources and licenses

Everything in `App/Resources/bible.sqlite` is built by `data/build_bibles.py` from the sources below.
No data from `/Applications/精读圣经.app` or `~/Library/Containers/cz.jdbible` was used.
License fields were checked on 2026-10-28 against the HelloAO `available_translations.json` metadata
(`license.publicDomain == true`; the build aborts if a translation stops being flagged public domain)
and against the eBible.org catalogue (`https://ebible.org/Scriptures/translations.csv`).

Delivery channel for the four Bible texts: HelloAO Free Use Bible API
(https://bible.helloao.org/, docs https://bible.helloao.org/docs/), file `/api/{id}/complete.json`
(one request per translation). HelloAO itself is a free-use mirror of eBible.org texts.

## Translations

| DB id | Name | Source | License |
|---|---|---|---|
| CUV | 新标点和合本 (Chinese Union Version, simplified script), HelloAO id `cmn_cu1` | https://ebible.org/Scriptures/details.php?id=cmn-cu89s (via https://bible.helloao.org/api/cmn_cu1/complete.json) | Public Domain. Statement: https://ebible.org/Scriptures/details.php?id=cmn-cu89s ("public domain"). Attribution not required. |
| RV1909 | Santa Biblia - Reina Valera 1909, HelloAO id `spa_r09` | https://ebible.org/Scriptures/details.php?id=spaRV1909 (via https://bible.helloao.org/api/spa_r09/complete.json) | Public Domain. Statement: https://ebible.org/Scriptures/details.php?id=spaRV1909. Attribution not required. |
| KJV | King James (Authorized) Version, 1769 standard text, HelloAO id `eng_kjv` | https://ebible.org/Scriptures/details.php?id=eng-kjv2006 (via https://bible.helloao.org/api/eng_kjv/complete.json) | Public Domain outside the UK. Statement: https://ebible.org/Scriptures/details.php?id=eng-kjv2006 (copyright page `copr.htm` inside the USFM zip). **UK caveat:** Crown letters patent (Cambridge/Oxford University Presses, Collins) restrict *printing/importing printed copies* in the United Kingdom; this does not affect other jurisdictions. A UK App Store release of a digital app is generally not "printing", but get a legal opinion if the UK is a target market. |
| ASV | American Standard Version (1901), HelloAO id `eng_asv` | https://ebible.org/Scriptures/details.php?id=eng-asv (via https://bible.helloao.org/api/eng_asv/complete.json) | Public Domain. Statement: https://ebible.org/Scriptures/details.php?id=eng-asv. Attribution not required. |

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
