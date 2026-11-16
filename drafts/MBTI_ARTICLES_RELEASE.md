# Revised introduction, groups and parent guides — v2.0.8

The eight supplied PDFs replace the active readers for `mbti_intro`, `mbti_groups`
and `mbti_parents`. The 20 temperament/type documents and student prescriptions
remain in their existing library.

| Menu | Documents | Sections |
|---|---:|---:|
| Introduction | 2 | 13 |
| Six learning groups | 1 | 10 |
| Parent guidance (overview, SJ, SP, NF, NT) | 5 | 31 |
| Total | 8 | 54 |

`mbti-library.js` supplies the same safe text/table renderer, revision-aware
editor, section/document trash and current-content print/PDF workflow for all
four menus. `mbti-articles.js` configures the first three menus. Retired article
records are retained, but the old reader/editor is not mounted.

The new private `mbti_articles` table and four RPCs use the existing approved,
active principal/director/manager role guard. No anonymous execution or direct
authenticated table grants are provided. Deletes leave tombstones; seed imports
use `ON CONFLICT DO NOTHING`, preserving edits and permanent deletions. Empty
trash checks a revision snapshot before deleting archived content.

Seven PDFs were extracted locally with all non-footer glyphs accounted for.
The image-only introduction letter was transcribed from all three rendered pages
and visually checked. The accidental `ㅜㅜㅎ` suffix in the other introduction's
fifth heading was removed; no substantive guidance was rewritten. Source hashes
and page counts are in the imported JSON. No paid recognition API was used.

Validation:

- Isolated PostgreSQL: role guard, revision conflict, variable section counts,
  invalid section rejection, edit/archive/restore/purge/empty-trash and seed
  idempotence.
- DOM: all 8 documents/54 sections, route changes and dirty-content guard,
  safe tables, exports, read-only controls and stale-account isolation.
- Actual local PDF generation for all 8 documents (3–10 A4 pages each), including
  final text; rendered sample pages checked for Korean and table pagination.
- Existing 20-document UI, per-student prescriptions and shared mobile PDF
  workflow pass. Native mobile sharing is mocked in the automated check; physical
  iPhone/iPad printer and file-save dialogs were not exercised.
- Production seed body hashes match local imports. RLS and RPC/table grants
  verified; existing type-document count remains 20.

Jekyll excludes import data, maintenance scripts, drafts and fixtures from the
deployed website. Runtime document reads use the guarded database RPCs.
