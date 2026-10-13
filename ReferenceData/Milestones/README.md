# Milestone catalog provenance

Reviewed October 10, 2026. The app ships a static, offline catalog. It does not scrape a site, download milestone media, or send family notes to a model.

## CDC

`cdc-checklists.json` freezes **100 skills**, in eight checklists at 2, 4, 6, 9, 12, 15, 18, and 24 months. Counts are 11, 13, 12, 13, 10, 13, 15, and 13. Each page has its canonical URL, published update date, retrieval date, SHA-256 of the retrieved HTML, and counts for all four source domains. Only the lists directly under Social/Emotional, Language/Communication, Cognitive, and Movement/Physical headings are extracted. Modal captions, tips, and repeated media are excluded. Wording is kept verbatim, including pronouns and examples, so the checklist meaning is not changed.

- [Official checklist index](https://www.cdc.gov/act-early/milestones/index.html)
- [Combined printable checklists](https://www.cdc.gov/act-early/media/pdfs/2025/10/cdc-milestone-checklists-ltsae-english-508.pdf)
- [Checklist age guidance](https://www.cdc.gov/wic-guide/php/administer-milestone-checklists/four-simple-steps.html)
- [CDC reuse policy](https://www.cdc.gov/other/agencymaterials.html)

Source: CDC. CDC materials are also available free on its website. CDC, HHS, and the U.S. Government do not endorse Swaddle. No CDC logos, photographs, or videos are reused. Attribution, the free-source notice, and non-endorsement wording are also in the app's Sources & age guidance screen.

Regenerate Swift deterministically from the reviewed JSON:

```sh
python3 scripts/generate_milestone_catalog.py
```

Only during a deliberate content update, use `--fetch`, then review the JSON diff against the linked official pages and printable checklists. **Existing IDs must remain stable when wording changes**; an upstream anchor change must be reconciled manually rather than duplicating a skill. A new reviewed edition needs a new source version and retrieval date. Observations retain their original source version and skill wording.

## WHO

The six ranges in `MilestoneCatalog.motorSkills` are numeric facts transcribed from the [official window table](https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/motor-development-milestones/mm_windows_table.pdf?sfvrsn=cb31ec78_5), accessed October 10, 2026. Source edition: WHO Motor Development Study, 2006, Acta Paediatrica Supplement 450:86–95; DOI 10.1111/j.1651-2227.2006.tb02379.x.

| Skill | 1st–99th percentile window, months |
| --- | --- |
| Sitting without support | 3.8–9.2 |
| Standing with assistance | 4.8–11.4 |
| Hands-and-knees crawling | 5.2–13.5 |
| Walking with assistance | 6.0–13.7 |
| Standing alone | 6.9–16.9 |
| Walking alone | 8.2–17.6 |

The official table's **6.0**, not the abstract's 5.9, is intentionally used for assisted walking. The app shows broad reference windows, without a moving child marker, percentile calculation, deadline, or developmental score. WHO observations remain separate from CDC checklist observations because definitions and reference methods differ.

## Age and observations

Use the younger completed calendar-month checklist and show the next as Looking ahead. Before two months, there is no current checklist. For births before 37 weeks, use the estimated 40-week due date until the second chronological birthday, following CDC's linked [AAP guidance](https://www.healthychildren.org/English/ages-stages/baby/preemie/Pages/Corrected-Age-For-Preemies.aspx). After the collection's age range, preserve history and link to CDC's older checklists. Missing birth date means browse manually; missing gestation means birth age, with explicit explanatory copy.

Every check-in is a first-class version-4 `RecordEnvelope.milestone` revision in the existing family CloudKit zone. There are **no new CloudKit record types or Core Data entities**, no migration, and no new sharing permissions. Older clients must update before they can interpret these records. New check-ins have independent IDs; edits capture the heads present when editing begins, preserving competing offline corrections. Deletions are reversible tombstones. Observations do not enter intake totals or care-history search.

Concern/lost-skill copy directs families to the child's doctor and developmental screening without waiting for another checkpoint. This catalog is not a validated screening tool and does not diagnose developmental delay.
