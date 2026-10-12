# Central translation workspace

Edit translations here. Each locale has **one PO file** containing interface,
Visual Enhancements, Multiplayer and available original-game text translations:
`de.po`, `es.po`, `fr.po`, `it.po`, `ko.po`, `pt_BR.po`.
AppLocalization is the only catalog loader. Features use `tr()` or
`AppLocalization.message()` for legacy feedback that arrives already formatted.
Never translate user chat, names, file paths, network identifiers or saved values.

`messages.pot` is the shared English **interface template** for translators and
PO editors. English `msgid` strings are also the application's English text; an
`en.po` copy is unnecessary. Message contexts distinguish original resources,
newspaper phrases, scenario descriptions and ambiguous UI terms. Original
newspaper IDs vary by edition, so they are deliberately not a shared UI template.
Their complete translations and provenance remain in each locale's PO file.

## Adding or changing a feature

1. Write the English source text. Translate before inserting dynamic values:
   `tr("Player: %s") % player_name`. Reuse an existing key when its meaning matches.
2. Add or update the key and context in `messages.pot` and **every registered
   language** in the same feature change. Include tooltips, errors, confirmations,
   menu items, empty states and dynamically assembled messages. A PO editor can
   merge the template into a new language catalog. Do not fill gaps with English.
3. Use supplied original SimCity 2000 wording where applicable. Otherwise author
   a supplementary translation using the existing terminology. Keep a source
   comment; describe new source editions in [localization-sources.md](../../../docs/localization-sources.md).
4. Only for legacy messages formatted before reaching the local UI, add their
   English template to `formatted_messages.json`, with specific templates before
   general ones. It stores source keys, not a second set of translations.
5. Run `python tools/check_localization.py` from the repository root, then the
   localization and affected UI tests through `tools/validate_project.sh`.
   The catalog check is included in the UI, headless and release suites. Verify
   runtime language switching, placeholders and representative dialog/tooltip fit.

`source_audit.json` also scans Visual and Multiplayer source literals, including
data-driven labels. Add new feature source paths here. Its exclusions identify
only internal IDs and theme names; they must never hide untranslated display text.

New languages must be registered in `AppLocalization.LANGUAGES` and `TRANSLATIONS`
and supply all shared UI template entries. Check font coverage too. Original-game
newspaper tables need a separate edition-specific extraction and mapping.

## Scope and provenance

Visual and Multiplayer translations are supplementary OpenSC2K translations from
the English feature source, assisted by AI. Existing original-game translations
retain their source comments unchanged. No game data package is needed to select
a language; original gameplay assets are still required to play.

Korean now includes the Visual and Multiplayer additions. The older base-game
catalog still has 328 missing shared UI entries, explicitly marked
`legacy-ko-fallback` in the template. These are pre-existing gaps, not permission
to omit translations for new features. The checker tolerates only these named
Korean gaps. No Korean original-game text edition has been supplied. Entry
coverage does not substitute for native-speaker editorial review.
