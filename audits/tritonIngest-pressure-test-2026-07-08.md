# tritonIngest ingestion pressure test — 2026-07-08

> **Status: all nine root causes fixed** on branch `fix/ingest-root-causes`
> (tritonIngest 0.6.0). See `NEWS.md` for the change list and the breaking
> changes. The findings below are preserved as the as-of-2026-07-08 diagnosis;
> the data defects in §9 are properties of the source files and remain open with
> the data provider.

**Scope:** five real lab/field deliverables driven end-to-end through the shipped
`tritonIngest` API (R 4.6.0, `Rscript --vanilla`, package sourced from `R/*.R`).
No package code was modified. No input file was modified.

**Method:** nine independent probes ran real R against the real package; every finding was
then attacked by three adversarial verifiers (independent re-run / source-accuracy /
severity-and-impact), majority-refutation discarding the claim. 86 findings raised,
74 survived. A completeness critic then hunted for unrun modalities. Findings below are
only those I could reproduce myself, with the verifiers' corrections folded in.

**Final verdict: `Ingestion failed` — for all five inputs, for five different reasons.**

---

## 1. Inputs and what they actually are

| # | File | Declared | Actually | Shape | Orientation |
|---|---|---|---|---|---|
| 1 | `effluent_lab_data_2025.csv` | CSV | CSV | 123 col × 5 row | wide |
| 2 | `effluent_lab_data.csv` | CSV | CSV, **UTF-8 BOM**, embedded newlines | 105 col × 47 row | wide |
| 3 | `6182_effluent_field_data.xlsx` | XLSX | XLSX, 3 sheets | see §2 | wide |
| 4 | `Q3_Q4_2024_Effluent_Monitoring_Lab_Data.xlsx` | XLSX | XLSX, 9 sheets | see §2 | **transposed** |
| 5 | `Q4_2025_marine_lab_data.csv` | CSV | **XLSX (ZIP) with a `.csv` extension** | 181 × 148 | **transposed** |

File 5 begins `50 4B 03 04` (`PK\x03\x04`) and contains `[Content_Types].xml`,
`xl/workbook.xml`, `xl/worksheets/sheet1.xml`. `readxl::excel_sheets()` opens it fine.

---

## 2. All sheet names (requirement: "load all sheets, incl. hidden / oddly-named / partially empty")

### `6182_effluent_field_data.xlsx`
| Sheet | State | Dimension | Merged ranges |
|---|---|---|---|
| `clean` | visible | A1:O140 | 16 |
| `cleaning` | visible | A1:P140 | 17 |
| `raw` | visible | A1:Q191 | 112 |

No `state=` attribute exists in `xl/workbook.xml` → **0 hidden sheets**. `sheetId` = {1, 2, 4};
the gap at 3 proves a sheet was deleted, and nothing more. Tab order is the reverse of creation
order (`raw`=1, `cleaning`=2, `clean`=4).

### `Q3_Q4_2024_Effluent_Monitoring_Lab_Data.xlsx` — 9 sheets, 0 hidden
`ShortTermGL`, **`BCWQ & CSR_metals comparison`**, `Dis Al calc`, `NH4 BCWQ Calculator`,
`BCWQ pH-T-Nit`, `BCWQ Cu WQG Data` (26 835 rows), `Mn CCME Calculator`, `Mn Look-up table`,
`Mn Calculator Instructions`.

### `Q4_2025_marine_lab_data.csv` — 1 sheet: `Sheet1`

### Verdict on the requirement
**Not satisfiable with the public API.** `tritonIngest` exports no worksheet enumerator —
the string `excel_sheets` occurs nowhere in `R/`, `man/`, `tests/`, or `NAMESPACE`, and `readxl`
is called at exactly one site (`R/read.R:38`). `read_tabular(path)` with `sheet = NULL` silently
reads **sheet position 1 only**, with no warning, message, or attribute recording that other
sheets existed:

* file 3 → returns `clean` (139 × 15); `cleaning` and `raw` dropped on the floor.
* file 4 → returns `ShortTermGL`, a **guideline lookup table**, not water-quality data.

Hidden sheets (verified on synthetic workbooks): `readxl::excel_sheets()` *does* list `hidden`
and `veryHidden` sheets and `read_tabular()` reads them — but neither exposes **visibility state**,
so a `veryHidden` sheet in position 1 is read as the default with no signal.

Sheet-name matching is exact: `sheet = "Cleaning"` → `Sheet 'Cleaning' not found`;
`sheet = 4` → `Can't retrieve sheet in position 4, only 3 sheet(s) found.`;
`sheet = 0` → `` `sheet` must be positive ``. A sheet named `"clean "` (trailing space) is
unreachable by its trimmed name.

---

## 3. Selected water-quality sheet and justification

Scorer criteria: (a) >10 analyte fields, (b) detection-limit notation, (c) numeric analyte
results, (d) valid date/time. Executed against every sheet.

### File 3 — `6182_effluent_field_data.xlsx`

| Sheet | analyte fields | `<` cells | `>` cells | numeric cells | date+time | header intact | matches |
|---|---|---|---|---|---|---|---|
| `clean` | 13 | 194 | 8 | 891 | yes | yes | **yes** |
| `cleaning` | 13 | 193 | 1 | 870 | yes | yes | **yes** |
| `raw` | 2 | 193 | 1 | 910 | yes | **no** (13 of 17 names are `...N`) | no |

`raw` fails criterion (a) *as `read_tabular()` reads it*: its header is a 2–3 row merged block, so
`col_names=TRUE` promotes the group labels (`Field Parameters`, `Physical and Chemical Parameters`)
and demotes the analyte names into data row 1.

**The caller's tiebreak — "largest number of analyte fields" — does not resolve.** `clean` and
`cleaning` tie at exactly 13, and their columns 1–15 are *positionally identical, character for
character*. `cleaning` merely appends `Certificate of Analysis` at column 16.

**Selection: `cleaning`,** against the naive parse-rate preference for `clean`. Justification:

* `clean` is a lossy derivative. It strips 27 of 28 lab data-qualifier flags (`a`,`b`,`c`,`d`,`RRR`,`DLA`)
  and all Certificate-of-Analysis numbers — both regulatory metadata.
* The stripping is **incomplete**: `178d` survives into `clean`'s BOD5 column.
* `clean` has lost information the other sheets retain: at serial 45622 `Temp` is `0.2` in `clean`
  but `-0.2` in `cleaning` and `raw` (one sign flip); at serial 45601 Rainbow-Trout survival is
  `100` in `clean` but `1` in `cleaning` — a 100× disagreement consistent with an Excel percent
  format (`1` displayed as `100%`).
* Cost of choosing `cleaning`: its missing marker is `"-"`, not blank, which the package mishandles (§6).

### File 4 — `Q3_Q4_2024_...xlsx`

Only **`BCWQ & CSR_metals comparison`** is water-quality data. It is the sole sheet containing an
explicit `Analyte` cell (A5) and a `Units` cell (B5).

A naive heuristic **false-positives on the calculator sheets**: `Dis Al calc` contains a `<0.0050`
token and Excel serial dates, and so passes "(b) DL notation + (d) dates + (c) numeric results".
`Mn CCME Calculator` likewise contains `<0.0050`. Discriminating them requires the `Analyte`/`Units`
keyword plus the section-divider structure — nothing the package offers.

### Sheet-selection failure report path
Never exercised, and **not implementable package-side**: with no sheet enumerator, both the
heuristic and its failure report must be caller code that does not exist.

---

## 4. Detected orientation (wide vs long vs transposed)

`detect_layout()` returns **`"wide"` for all seven cases tested** (both CSVs, all three sheets of
file 3 both raw and cleaned). Nothing in this corpus is misclassified as long. But:

* **There is no long-format sheet anywhere in this corpus.** All of file 3 is wide. Files 4 and 5
  are *transposed* (analyte × sample matrices), an orientation `tritonIngest` does not model.
* On file 4's metals sheet, `clean_table()` promotes the **Sample Location** row to column names,
  yielding `ETP Pond`, `ETP Pond_1`, …, `Basin 2_4`, `POC_5`. `detect_layout()` then reports
  `wide` with **23 value-like columns — which are samples, not analytes**. Melting on them would
  emit `parameter = "ETP Pond"` for every measurement. `"analyte" %in% tolower(names(tt))` is
  `FALSE` because `Analyte` is a *cell* (A5), not a column name.
* **The name rule overrides the evidence.** Renaming any one column of the 123-column wide CSV to
  `Result` flips `detect_layout()` to `"long"` while it simultaneously reports 120 value-like
  columns. Verified.
* `is_value_like()` degrades badly on `cleaning`: the `"-"` missing marker is neither numeric nor an
  ND token, so only **4 of 13** analyte columns score as value-like (vs 13 on `clean`). Still ≥2, so
  the layout call stays `wide` — but a caller who feeds `value_like_cols` into `melt_wide()` as
  `param_cols` silently drops 9 analytes.

---

## 5. Schema comparison across sheets

### File 3 — inter-sheet
`clean[1:15]` ≡ `cleaning[1:15]` positionally and textually. **No inter-sheet positional shift exists.**

### File 3 — intra-`raw` (the real defect)
`raw` is a paginated print report: header blocks at rows 1, 72, 122, 157, 181; `Permit limit` rows at
5, 76, 126, 161, 185; one-cell banner/footnote rows at 65, 115, 150, 175–180, 190–191.

**Blocks 4–5 insert an interior blank column at position 8**, shifting every analyte from Ammonia
rightward by one:

```
block 1 header (row 2):   [7] TSS (mg/L)  [8] Ammonia (Total) (mg/L)  [9] Phosphorus …
block 4 header (row 158): [7] TSS         [8] <blank>                 [9] Ammonia (Total) …
```

`clean_table()` promotes the block-1 header and applies it to all 136 data rows. Consequently the
17 data rows on pages 4–5 are relabelled: Ammonia → Phosphorus, BOD5 → COD, Fecal Coliforms →
Rainbow Trout % survival. Column 14 therefore holds both `>2420a` (Fecal, block 1) and `<0.25`
(EPH C19-C32, block 4). Column 17 — which the workbook's own `<dimension>` and my first pass both
treated as empty — actually carries **19 Certificate-of-Analysis values** from blocks 4–5.

Blocks 4–5 also use a **structurally different 3-row header** (units demoted to row 3 for every
column), and block 5 appends a footnote digit `1` to three units. `raw` thus contains three
spellings of the same analyte: `TSS (mg/L)` / `TSS (mg/L)1`, `Temp` / `Temp (°C)`,
`EPH C10‑C19 (mg/L)` / `EPH C10‑C19`. `.cf_norm()` maps these to `tss_mg_l` vs `tss_mg_l_1` and
`temp` vs `temp_c` — different contract keys. Even a correct multi-row-header reader would fail to
reconcile the blocks.

### Required fields Date / Time / Sample / Analyte / Result

| source | date | time | sample | analyte | result |
|---|---|---|---|---|---|
| `clean` | `Date` | `Time` | — | — | — |
| `cleaning` | `Date` | `Time` | — | — | — |
| `raw` | `Date` | `Time` | — | — | — |
| CSV #1 | `Date` | — | `Sample` | `Analyte` ⚠ | — |

**None of the three XLSX sheets has a Sample, Analyte, or Result column at all** — they are wide.
`grep("sampl|site|station|location", names(d), ignore.case=TRUE)` returns `character(0)` on all
three. Melting does not fix `sample`; **it is nowhere in the workbook.** The CSV's `Analyte` column
is a constant matrix label (all values `"Effluent"`) — see §7.

`melt_wide()` mints `parameter` / `value_raw` / `units`, never `analyte` / `result`.

### Blank leading columns
**None**, on any sheet or CSV. `drop_blank_cols(raw)` correctly removes nothing. The analogous real
defect is the *interior* blank column at `raw` position 8, which nothing detects.

---

## 6. Detection-limit parsing

`parse_censored()` has a `"<DL"` branch and an ND-token branch. It has **no `">"` branch.**

| token class | result | example |
|---|---|---|
| `<3.0`, `<0.0050` | `censored=TRUE`, DL recovered | correct |
| `ND`, `BDL`, `U` | `censored=TRUE`, `DL=NA` | correct-ish |
| **`>2420`, `>80`, `>17.1`, `>60`, `TNTC`** | `value=NA`, `censored=NA`, `"unparseable result text"` | **erased** |
| **`178d`, `0.06b`, `143 a`, `114c,RRR`, `MBEF <1`, `<10 DLCI`, `DTC 0.00842`** | `value=NA`, `censored=NA` | **erased** |
| **`-`** (files 3–5 missing marker) | `value=NA`, `censored=NA`, `"unparseable"` | **not recognised as missing** |
| `""` (blank) | `censored=NA`, `"missing"` | correct |

`ND_LT_REGEX = "^<\\s*[0-9.eE+-]+$"` also matches **`"<-"`, `"<."`, `"<e"`, `"<+-"`** → `censored=TRUE`,
`detection_limit=NA`, `parse_note=NA` (i.e. silently "clean").

The right-censored losses are precisely the regulator-relevant cells: on `clean`, 8 cells —
`>2420`×2 and `>80`×3 in **Fecal Coliforms** (permit limit 40 CFU/100 mL) and `>17.1`/`>45.5`/`>46.9`
in **BOD5** (permit limit 45). `>2420` is the standard MPN upper bound; losing it converts a known
exceedance into a missing value.

### Detection-limit heterogeneity within a column (nothing flags this)
| analyte | DLs present | range |
|---|---|---|
| Ammonia (Total) | 0.005, 0.1 | **20×** |
| EPH C10-C19 / C19-C32 | 0.02, 0.2, 0.25 | 12.5× |
| Fecal Coliforms | 1, 2, 10 | 10× |

Substituting `DL/2` across a column whose DL varies 20× injects a step artefact into the series.

---

## 7. Columns failing type coercion

`.cf_coerce(x, "numeric")` is `suppressWarnings(as.numeric(x))`. `apply_column_map(coerce=TRUE)`
therefore destroys every non-detect **before** `parse_censored()` is ever reached. The two halves
of the package do not compose.

`clean` sheet, per-column non-coercible fraction:

| column | n | fail | % | `validate_against_contract()` |
|---|---|---|---|---|
| EPH C10-C19 | 44 | 43 | 97.7 | `type_warn` |
| EPH C19-C32 | 44 | 43 | 97.7 | `type_warn` |
| Fecal Coliforms | 43 | 31 | 72.1 | `type_warn` |
| BOD5 | 46 | 22 | 47.8 | **`ok`** |
| Ammonia (Total) | 46 | 22 | 47.8 | **`ok`** |
| TSS | 55 | 24 | 43.6 | **`ok`** |
| COD | 46 | 16 | 34.8 | **`ok`** |
| Turbidity, pH | 121/120 | 1 | 0.8 | `ok` |

The `type_warn` threshold is `n_bad / length(x) > 0.5` where **`length(x)` includes the NAs**. On the
full BOD5 column that is `22/137 = 0.161`. A sparse column can never trip the threshold no matter
how much of its *data* is unparseable. Eight columns silently lose 0 < x ≤ 50 % of their values
while validation reports `ok`.

---

## 8. Rows failing validation

| source | rows in | junk rows surviving `clean_table()` | detail |
|---|---|---|---|
| `clean` | 137 | 1 | `Permit limit` row (Date → NA, warned) |
| `cleaning` | 137 | 1 | idem |
| `raw` | 167 | **31** | 15 repeated-header, 5 `Permit limit`, 11 banner/footnote |
| file 4 metals | 120 | 11 | single-cell section dividers |

`clean_table()` drops only **fully blank** rows — documented and deliberate. The consumer
`waterqaqc::drop_label_rows()` (rows with < 2 non-blank cells) is the existing fix; `tritonIngest`
ships no equivalent.

**The `Permit limit` row is the sharpest case.** It is not blank, so it survives and melts into 13
ordinary measurement rows (65 on `raw`). Ten of its 13 cells are clean numerics:
`Temp=23, TRC=0.03, TSS=75, Ammonia=10, Phosphorus=2, BOD5=45, COD=100, EPH=10/10, Fecal=40`.
`BOD5 = 45` becomes a BOD5 *measurement* of exactly its own permit limit. Its only signal is
`coerce_excel_date()`'s warning on the string `"Permit limit"` — which `suppressWarnings()` erases.

Other row-level defects, none detected by any package function:

* 7 duplicate `(Date, Time)` keys in `clean`/`cleaning`.
* Serial **45951** (2025-10-21) sits between 45583 (2024-10-18) and 45588 (2024-10-23) — the single
  backwards step in an otherwise monotonic series, and the file's maximum date. The workbook's own
  ordering brackets the intended value to 45584–45587; **the exact value is not determinable** and
  needs the lab's confirmation.
* CSV #1 mixes site codes `POC` (4 rows) and `POC1` (1 row).
* File 5 contains **20 QA/QC columns** — 5 field blanks (`FB`), 5 trip blanks (`TB`), 10 blind
  duplicates (`IDZ-N-3-A`, `WQ9-37-A`, …) — which are not environmental samples and must not be
  ingested as such.

### Usable-data census

| source | cells | detected | left-censored (DL) | unparseable | usable |
|---|---|---|---|---|---|
| `clean` (melted) | 864 | 658 | 194 | 12 | 852 (98.6 %) |
| CSV #1 analyte matrix | 600 | 199 | 0 | 0 | **199 (33.2 %)** |
| file 4 metals (transposed) | 2 231 | 940 | 1 272 | 19 | 2 212 (99.1 %) |

CSV #1's 386 `ND` cells carry **no detection-limit column anywhere in the file**, so
`working_values()` returns `NA` for every one: 64.3 % of the matrix is censored-but-unusable.
**63 of its 120 analyte columns (52.5 %) carry zero numeric information** — the entire VOC/BTEX and
PAH suites, plus 26 metals.

---

## 9. Confirmed data defects (independent of the package)

### D1 — `effluent_lab_data_2025.csv` column 68 is **Manganese**, labelled `Magnesium_Mg_Total` — *proven*
`Magnesium_Mg_Total` appears at positions **68 and 84**; `Manganese_Mn_Total` appears nowhere,
though `Manganese_Mn_Dissolved` does. The Total and Dissolved blocks are otherwise 35-analyte
positional mirrors, and they diverge at exactly one offset (16).

The two effluent CSVs overlap on **2025-09-04**. On that date, for both samples:

| | `effluent_lab_data.csv` (correct headers) | `effluent_lab_data_2025.csv` |
|---|---|---|
| `Manganese_total` | 0.138 / 0.137 | `Magnesium_Mg_Total...68` = **0.138 / 0.137** |
| `Magnesium_total` | 1.8 / 1.8 | `Magnesium_Mg_Total...84` = **1.8 / 1.8** |

Cell-for-cell identical. This is a direct cross-file value match, not an inference from the
total ≥ dissolved constraint.

**How the package responds depends on the read path — both are bad:**
* `read_tabular()` (readr default repair) → names become `...68` / `...84`. `.cf_norm` yields
  `magnesium_mg_total_68`, edit distance 3 from `magnesium_mg_total` (budget 2), so `auto_map()`
  matches **neither**; both metals report `missing → error`. It fails loudly — but the `_Total$`
  family regex now counts **33 instead of 35**.
* `name_repair = "minimal"` → the duplicate survives; `auto_map()` exact-matches the **first**
  `Magnesium_Mg_Total` → column 68 → **Manganese values ingested as Magnesium**, and
  `Manganese_Mn_Total` reported absent.

Neither `read_tabular()` nor `clean_table()` ever calls `anyDuplicated()`. readr's rename is a
**message**, silenced entirely by `suppressMessages()`. `clean_table()`'s `make.unique()` produces
*different* names again (`Magnesium_Mg_Total_1`), so the CSV and Excel paths disagree on the same defect.

### D2 — a **365-day** date error in `Q3_Q4_2024_...xlsx`
LAB ID `VA24C1052`, `ETP Pond`, `Time Sampled = 0.375`:

| source | date |
|---|---|
| `Q3_Q4_2024` metals sheet | serial **45887** → 2025-08-18 |
| `6182` `cleaning` sheet (same COA) | serial 45522 → 2024-08-18 |
| `effluent_lab_data.csv` (same site, same analyte values 42.4 / 38.3 / 2.19) | `18-08-2024` |

Two independent sources agree on 2024-08-18; the serials differ by exactly 365. The `VA24` prefix
encodes 2024. The workbook's other serial (45642 → 2024-12-16) correctly brackets its neighbours
`09-Dec-24` and `26-Dec-24`. `coerce_excel_date()` cannot catch this: 45887 is a perfectly valid serial.

### D3 — `Q3_Q4_2024` calculator sheets are fed misaligned inputs
`Dis Al calc` and `NH4 BCWQ Calculator` carry `pH` = 42.4, 43.3, 31.1 (pH is bounded 0–14) and
`Temperature (°C)` = 38.3, 43.6, 33.2 (the 6182 field data records 5.9–20.5 °C). `Dis Al calc`'s
`Hardness (mg/L)` column holds `<0.0050`, a detection-limit string. Its rows reference station
`CapPS` dated 2023-10-12 — an unrelated study. The values 42.4 / 43.3 are the metals sheet's
*dissolved hardness*; 38.3 / 43.6 its *total hardness*; 2.19 / 1.9 its *TOC*. Every guideline and
`Exceedance?` value derived on these sheets should be treated as unreliable.

### D4 — `6182` `clean` sheet lost information
One sign flip (serial 45622: `0.2` vs `-0.2` in `cleaning`/`raw`) and a 100× Trout disagreement
(serial 45601: `100` vs `1`).

---

## 10. Root causes

| # | Root cause | Evidence | Files hit |
|---|---|---|---|
| RC1 | **No sheet-level API.** No enumerator; `sheet=NULL` silently reads sheet 1. | `excel_sheets` absent from `R/`; file 4 default read returns a guideline table | 3, 4 |
| RC2 | **Extension-based dispatch, no magic-byte check.** `read.R` switches on `tools::file_ext()`. | file 5 (a ZIP) → `read_tabular()` returns a **1 × 1 tibble whose column name is `<?xml version="1.0" …?>`**, no error, no warning | 5 |
| RC3 | **Date coercion silently mangles day-first strings.** `as.Date()` prefix-matches: `%Y`←"18", `%m`←"08", `%d`←"20", trailing "24" discarded. | `coerce_excel_date("18-08-2024")` → **`0018-08-20`**, 0 warnings; **47 of 47** rows of file 2 land in years 2–30 AD | 2 |
| RC4 | **Censoring model is left-only.** No `">"` branch. | `>2420`, `>80`, `TNTC`, `>60` → `value=NA, censored=NA` | 3, 2, 4 |
| RC5 | **The halves don't compose.** `apply_column_map(coerce=TRUE)` coerces before `parse_censored()` runs. | 386 ND cells → NA silently; 194 left-censored cells lost on `clean` | 1, 3 |
| RC6 | **Name-based mapping with a fuzzy fallback is unsafe.** | `analyte`→`"Analyte"` matrix label; `dl`↔`pH` at adist 2; `LEPH_C10_C19`→`EPH_C10_C19` at adist 1; order-dependent; duplicates never checked | 1 |
| RC7 | **`clean_table()` is structural-only, by design.** Single-header model. | permit-limit rows, 31 junk rows in `raw`, section dividers, block 4–5 shift | 3, 4 |
| RC8 | **Validation kernel is column-level and count-only.** | `validate.R` = `check_required_columns`, `check_column_types`, `check_no_na`, `type_matches`, `validation_abort` | all |
| RC9 | **No transposed orientation.** `detect_layout()` knows long vs wide only. | files 4 and 5 are analyte × sample matrices | 4, 5 |

### RC6 in detail — the catastrophic case
On the melted CSV #1 with a realistically-synonymed contract:

```
auto_map()  ->  analyte = "Analyte"        # the matrix label, all 5 values "Effluent"
                result  = "value_raw"
                sample_date = "Date", sample_id = "Sample", units = "units"
apply_column_map()  ->  drops `parameter` (unreferenced source columns are discarded)
validate_against_contract()  ->  every required field "ok"
contract_is_ready()  ->  TRUE
```

**585 measurements across 120 distinct analytes are ingested as 585 rows of a single analyte named
`"Effluent"`, and the contract system reports the frame READY.** `analyte` exact-matches `"Analyte"`
before the synonym `"parameter"` (which holds the real analyte names) is ever consulted.

Two further fuzzy collisions, both confirmed 3/3 by adversarial verifiers:
* a `detection_limit` field carrying synonym `"dl"` binds to the **`pH`** column
  (`adist("ph","dl") == 2 ≤ max_distance`). Every censored value is then substituted with `0.5 × pH ≈ 3.7`.
* a `LEPH_C10_C19` field binds to **`EPH_C10_C19`** at edit distance 1, beating the correct
  `LEPH_C10_C19_less_PAH` at distance 9. LEPH and EPH are different regulatory quantities.

Tested and **did not** fire on this corpus: `Magnesium`↔`Manganese` (edit distance 6), and
`auto_map()` field-order dependence for the specific contracts tried.

Also confirmed: a **zero-row frame passes `contract_is_ready()`** with every required field `"ok"`.

---

## 11. Normalisation

`.cf_norm()` (`contract.R:63-67`) does `tolower(trimws(x))` → `gsub("[^a-z0-9]+","_")` → strip edges.
Measured behaviour:

* trim and whitespace-collapse: correct.
* **U+2011 NON-BREAKING HYPHEN** (used in `EPH C10‑C19` / `C19‑C32`) and ASCII `-` both fold to `_`,
  so `auto_map()` exact-matches across the hyphen difference. A claim that U+2011 breaks mapping
  would be false — it was raised and **refuted 3/3**.
* Gaps: `.cf_norm` is **not exported**; no `iconv` anywhere in `R/` (so `°` survives as `_c`,
  `Temp (°C)` → `temp_c` ≠ `temp`); **no known-variant/alias dictionary ships** — `synonyms` are
  per-field and hand-authored.

Worked map for the 13 XLSX analytes (units split out, never discarded):

| source | canonical | units |
|---|---|---|
| `pH` | `ph` | — |
| `Temp` | `temp` | — |
| `Total Residual Chlorine (mg/L)` | `total_residual_chlorine` | mg/L |
| `Turbidity (NTU)` | `turbidity` | NTU |
| `TSS (mg/L)` | `tss` | mg/L |
| `Ammonia (Total) (mg/L)` | `ammonia_total` | mg/L |
| `Phosphorus (Total) (mg/L)` | `phosphorus_total` | mg/L |
| `BOD5 (mg/L)` | `bod5` | mg/L |
| `COD (mg/L)` | `cod` | mg/L |
| `Extractable Petroleum Hydrocarbons (EPH) C10‑C19 (mg/L)` | `eph_c10_c19` | mg/L |
| `Extractable Petroleum Hydrocarbons (EPH) C19‑C32 (mg/L)` | `eph_c19_c32` | mg/L |
| `Fecal Coliforms (CFU/100 mL)` | `fecal_coliforms` | CFU/100 mL |
| `Rainbow Trout 96 Hour Acute Lethality Test (% survival)` | `rainbow_trout_96h_acute_lethality` | % survival |

`convert_units()` covers only mass/volume and mass/mass ladders. `NTU`, `CFU/100 mL`, `% survival`,
`°C` all return `NA` with a warning. `melt_wide()` emits a `units` column that nothing validates.

Deliberate **non**-merges: `ammonia_total` (XLSX, total ammonia as N) vs `ammonia_as_n` (CSV) report
on different bases; merging them would be a scientific error a normaliser is not entitled to make.

---

## 12. Recommended canonical schema

Grain: **one row per `(source_file, source_sheet, source_row, sample_date, sample_time,
sample_point, replicate_id, analyte_canonical)`**. `value_raw` is the immutable record of truth and
is never coerced in place.

```r
effluent_long_contract <- list(
  # provenance
  cf_field("source_file",   "character", TRUE),
  cf_field("source_sheet",  "character", TRUE),
  cf_field("source_row",    "integer",   TRUE),
  cf_field("source_block",  "integer",   FALSE),  # print-block index for paginated reports

  # sample-event key
  cf_field("sample_date",   "date",      TRUE,  c("date","sample_dt","collection_date")),
  cf_field("sample_time",   "character", FALSE, c("time")),        # WANT time/hms
  cf_field("sample_time_raw","character",FALSE),                   # "08:46c,d" | "0.4027777"
  cf_field("sample_point",  "character", TRUE,  c("sample","station","site","location")),
  cf_field("sample_matrix", "character", FALSE, c("analyte","matrix","medium")),  # traps "Effluent"
  cf_field("replicate_id",  "character", FALSE),
  cf_field("lab_id",        "character", FALSE, c("certificate_of_analysis","coa")),

  # analyte identity
  cf_field("analyte_canonical","character", TRUE, c("parameter","determinand")),
  cf_field("analyte_source",   "character", TRUE),   # verbatim, U+2011 preserved
  cf_field("units",            "character", FALSE),

  # the measurement, decomposed
  cf_field("value_raw",       "character", TRUE),    # never coerced
  cf_field("value",           "numeric",   FALSE),   # NA when censored
  cf_field("censor_direction","character", FALSE),   # "none"|"left"|"right"  -- WANT enum
  cf_field("detection_limit", "numeric",   FALSE),
  cf_field("qualifier",       "character", FALSE),   # a,b,c,d,RRR,DLA,TNTC,MBEF,DTC,DLCI
  cf_field("is_qc_sample",    "character", FALSE),   # FB|TB|blind-dup  -- WANT logical
  cf_field("is_metadata_row", "character", FALSE)    # permit-limit / divider / banner
)
```

Types `cf_field()` **cannot** express and would need adding: `time`/`datetime`, `logical`, and an
`enum` (for `censor_direction`, sheet visibility, QC class).

**Duplicate source names must be quarantined, not repaired.** `Magnesium_Mg_Total...68/...84` map to
`NA` by default. The Mn/Mg reassignment (D1) is now *proven* by cross-file value match, so it can be
applied as an explicit, human-authored override — never inferred by the normaliser.

### Checks the package needs and does not have

| Check | Would have caught |
|---|---|
| `check_unique(data, key_cols)` | the 7 duplicate `(Date,Time)` keys; `anyDuplicated()` is never called in `R/` |
| duplicate-**input-name** check, before repair | `Magnesium_Mg_Total` at 68 and 84 (D1) |
| `check_range(data, bounds)` | pH 42.4 and Temp 43.6 °C in the calculator sheets (D3); % survival ∉ [0,100] |
| `check_monotonic_date(data, date_col)` | serial 45951; the bare-year `"2024"` → 1905-07-16 coercion |
| `check_not_metadata_row(data, predicate)` | the `Permit limit` rows (1× `clean`, 5× `raw`) and 31 junk rows |
| right-censor support in `parse_censored()` | `>2420`, `>80`, `>17.1`, `TNTC`, `>60` |
| `na =` argument on `read_tabular()` / `is_value_like()` | the `"-"` missing marker in files 3, 4, 5 |
| magic-byte sniff in `read_tabular()` | file 5 (a ZIP named `.csv`) |
| `excel_sheets()` wrapper + visibility state | RC1 |

---

## 13. Final verdict

**`Ingestion failed`** — for every input.

| file | verdict | decisive cause |
|---|---|---|
| `effluent_lab_data_2025.csv` | **failed** | 120 analytes collapse to one named `"Effluent"` while `contract_is_ready()` returns `TRUE`; col 68 is mislabelled Manganese; 66.8 % of the analyte matrix unusable |
| `effluent_lab_data.csv` | **failed** | all 47 dates silently coerced to years 2–30 AD, zero warnings |
| `6182_effluent_field_data.xlsx` | **failed** | only 1 of 3 sheets is reachable; permit limits ingested as measurements; `raw` blocks 4–5 relabel 17 rows; 8 permit exceedances erased |
| `Q3_Q4_2024_..._Lab_Data.xlsx` | **failed** | default read returns a guideline table; the data sheet is transposed (unsupported); 21 of 23 sampling dates → `NA`; a 365-day date error |
| `Q4_2025_marine_lab_data.csv` | **failed** | the file is an XLSX; `read_tabular()` returns a 1×1 tibble of XML text with no error |

Nothing here is unfixable. RC2 (magic-byte sniff), RC3 (reject a format match that leaves trailing
characters), RC4 (a `">"` branch), and the duplicate-input-name check are each a few lines and would
convert four of the five silent corruptions into loud failures. RC1, RC5, RC7 and RC9 are design
changes. RC6 argues for making `auto_map()`'s fuzzy stage opt-in (`max_distance = 0` by default) and
for never letting an exact match on a *column name* outrank a semantic synonym without confirmation.

---

### Method notes / limitations

* 12 of 86 findings were discarded on adversarial review. Two were reinstated here because I obtained
  evidence the verifiers did not have: the day-first date corruption (refuted as "no test file
  contains a day-first date" — `effluent_lab_data.csv`, supplied later, is 47 for 47) and the
  Manganese mislabel (refuted on its stated *mechanism*, while every verifier explicitly confirmed
  the data claim; now proven outright by cross-file value match).
* The `raw` blocks 4–5 column shift and the non-empty column 17 **corrected my own initial reading**
  of the workbook.
* The Trout `1` vs `100` discrepancy is reported as a raw-value disagreement between sheets. I did
  not resolve the cell's `numFmt` in `xl/styles.xml`; no custom `numFmt` is declared, so the percent-
  format hypothesis rests on the builtin formats 9/10 and remains unconfirmed.
* Reproduction scripts: `recon.R`, `recon2.R`, `recon3.R`, `recon4.R`, `recon5.R`, `ingest_attempt.R`,
  `addendum.R`, `file3.R`, `file45.R`, `file6.R`, `mgcheck.R`, `gapclose.R`, `tempsign.R` (session scratchpad).
