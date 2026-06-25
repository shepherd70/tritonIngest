# tritonIngest — Design Document

**Status:** Implemented (v0.4.3) — Phase 0–1 complete, plus an added validation
kernel and materialisation cache. Phase 2 done: `bw-analysis-code` consumes the
shared package (pinned `v0.4.3`); Phases 3–4 (`water-chemistry-qaqc`, chemistry
ingestion in bw) pending ·
**Author:** drafted for Travis Shepherd · **Date drafted:** 2026-06-08 ·
**Last reconciled:** 2026-06-24

A lean, domain-agnostic R package for **tabular data ingestion**: read messy
field/lab workbooks, detect their layout, map their columns onto a declared
schema, parse non-detects/units, and validate the result — shared by
`water-chemistry-qaqc` (chemistry) and `bw-analysis-code` (fish, effort,
habitat, and eventually metals).

---

## 1. Why

Both repos independently grew an ingestion layer, with real overlap and real
gaps:

- **`bw-analysis-code`** has the stronger *structural* design: a declarative,
  role-based **data contract** (`DATA_CONTRACTS` = catch/effort/fhap), synonym +
  fuzzy `auto_map()`, `validate_against_contract()`, and persisted JSON
  **mapping profiles**. But it has **no non-detect/censored handling and no
  chemistry contract** — even though it ingests tissue-metals and sediment
  workbooks.
- **`water-chemistry-qaqc`** has the stronger *lab-data* primitives: all-as-text
  reading, **long/wide layout detection + melt**, **non-detect parsing**
  (`<0.01`, `ND`, separate DL columns), substitution, and unit reconciliation.
  But its column mapping is a fixed `suggest_roles()` keyed to one hardcoded
  `wqdata` schema — far less general than bw's contract engine.

Neither is a superset. A small shared package lets each repo use the best of
both and stops the duplication from diverging.

**Non-goal:** this is **not** a place for domain knowledge — no fish biology, no
guideline tables, no `wqdata`/`catch` field lists, no statistics. Those stay in
the consuming repos. tritonIngest is *plumbing only*.

---

## 2. Scope

### In (the shared engine + utilities)

| Capability | Comes from today | tritonIngest API |
|---|---|---|
| All-as-text CSV/XLSX reader | wq `read_wq_file`, bw `read_aemp_excel` | `read_tabular(path, sheet = NULL, col_types = NULL, col_names = TRUE)` |
| Excel serial-date coercion | bw `coerce_excel_date` | `coerce_excel_date(x)` |
| Structural cleaning (header recovery, blank-row/col strip) | new | `clean_table(df, header_row = NULL, trim_ws = TRUE)`, `find_header_row(df)`, `drop_blank_rows(df)`, `drop_blank_cols(df)` |
| Value-likeness heuristic | wq `is_value_like` | `is_value_like(x, threshold = 0.8)` |
| Long/wide layout detection | wq `detect_layout` | `detect_layout(df)` (returns `$layout`, `$value_like_cols`, `$reason`) |
| Wide → long melt | wq `melt_wide` | `melt_wide(df, param_cols, id_cols, ...)` |
| Contract field spec | bw `.cf_field` | `cf_field(name, type, required, synonyms, description)` |
| Build/inspect a contract | bw `data_contract`, `contract_roles` | `as_contract(fields)`, `contract_fields()` |
| Synonym + fuzzy column auto-map | bw `auto_map` | `auto_map(source_cols, contract, max_distance = 2L)` |
| Apply a column map (rename/select/coerce) | bw `apply_column_map` | `apply_column_map(df, mapping, contract, coerce = TRUE)` |
| Validate a frame against a contract | bw `validate_against_contract` | `validate_against_contract(df, contract)` |
| Fill missing optional fields | bw `complete_to_contract` | `complete_to_contract(df, contract)` |
| Readiness check | bw `contract_is_ready` | `contract_is_ready(df, contract)` |
| Mapping-profile persistence (JSON) | bw `*_mapping_profile` | `save/load/list/delete_mapping_profile(...)`, `mapping_profiles_dir(dir)` |
| **Non-detect parsing** | wq `parse_censored` | `parse_censored(value_raw, detection_limit = NULL)` |
| **Substitution (½DL/DL/0)** | wq `apply_substitution` | `apply_substitution(value, censored, detection_limit, fraction = 0.5)` |
| **Working values switch** | wq `working_values` | `working_values(value, censored, detection_limit, method, fraction)` |
| **Unit reconciliation** | wq `convert_units` (currently in `checks_guideline.R`) | `convert_units(value, from, to)` |
| Generic validation kernel *(added post-design — see §5)* | new | `check_required_columns`, `check_column_types`, `type_matches`, `check_no_na`, `validation_abort` |
| Materialisation cache *(added post-design — see §5)* | new | `cache_dir`, `write_cache`, `read_cache`, `cached_ingest` (rds/parquet) |

### Out (stays in the consuming repos)

- **wq:** the `wqdata` model + accessors, the guideline engine + tables,
  censored *statistics* (`censored_stats` — pulls NADA/NADA2), plots, Shiny.
- **bw:** the domain `DATA_CONTRACTS` (catch/effort/fhap + new ones), analysis
  pipelines, explorers, `process_qaqc` domain rules.
- Anything needing `NADA`, `EnvStats`, `shiny`, `ggplot2`, or statistical models.

---

## 3. Architecture & principles

1. **Pure functions, no side effects** (except the explicit profile read/write).
   Cold-session unit-testable — both repos already hold this line.
2. **Contracts are data, passed in — never a hardcoded global.** This is the one
   substantive refactor vs bw's current code: bw's `auto_map(source_cols, role)`
   looks `role` up in the global `DATA_CONTRACTS`. In the shared package the
   functions take a **contract object** (or a registry handle), so each repo owns
   its own contracts. A thin compatibility shim in bw (`auto_map(cols, role)` →
   `auto_map(cols, DATA_CONTRACTS[[role]])`) preserves its current call sites.
3. **Lean dependencies.** Ingestion only. The as-built `Imports` are `readr,
   readxl, tibble, dplyr, tidyr, purrr, jsonlite` plus base `stats, tools,
   utils`; `arrow` is `Suggests`-only (the optional parquet cache backend). The
   originally-floated `rlang, stringr, here, lubridate` proved unnecessary and
   were dropped. No stats/plot/Shiny stack, so an import-only consumer stays
   light. Fuzzy matching uses base `utils::adist` (as bw already does) — no
   `stringdist` dependency.
4. **Backward-compatible migration.** Each repo keeps its current public function
   names as thin re-exports/aliases of the shared ones, so no downstream call
   site breaks during migration.

### The contract object

```r
contract <- as_contract(list(
  cf_field("year",      "integer",   required = TRUE,  synonyms = c("yr", "sample_year")),
  cf_field("site",      "character", required = TRUE,  synonyms = c("station", "site_id")),
  cf_field("length_mm", "numeric",   required = TRUE,  synonyms = c("fork_length", "fl_mm"))
))
```

A contract is just a list of field specs (name, type ∈ character/numeric/
integer/date, required, synonyms, description). The consuming repo holds a named
registry of these (bw's `DATA_CONTRACTS`; wq's new `wq_contract()`); tritonIngest
never sees the names.

### Typical consumer flow

```r
raw     <- read_tabular("2025 KO Spawner Raw Data.xlsx", sheet = "Data",
                        col_names = FALSE)            # read header-less...
tidy    <- clean_table(raw)                           # ...then recover header, drop blanks
layout  <- detect_layout(tidy)$layout                 # "long" | "wide"
long    <- if (layout == "wide") melt_wide(tidy, param_cols = ...) else tidy
mapping <- auto_map(names(long), contract)            # best-guess col -> field
mapped  <- apply_column_map(long, mapping, contract)  # rename/select/coerce
report  <- validate_against_contract(mapped, contract)
# chemistry only:
mapped$detection_limit <- parse_censored(mapped$value_raw)$detection_limit
mapped$working <- working_values(mapped$value, mapped$censored, mapped$detection_limit)
```

---

## 4. Package structure

```
tritonIngest/
  DESCRIPTION            # Imports: readr, readxl, tibble, dplyr, tidyr, purrr,
                         #          jsonlite, stats, tools, utils
                         # Suggests: arrow (parquet cache backend), testthat
  NAMESPACE              # generated by roxygen
  R/
    read.R               # read_tabular, coerce_excel_date
    clean.R              # find_header_row, clean_table, drop_blank_rows,
                         #   drop_blank_cols  (structural junk removal)
    layout.R             # is_value_like, detect_layout, melt_wide
    contract.R           # cf_field, as_contract, contract_fields, auto_map,
                         #   apply_column_map, validate_against_contract,
                         #   complete_to_contract, contract_is_ready
    profiles.R           # save/load/list/delete_mapping_profile, mapping_profiles_dir
    censored.R           # parse_censored, apply_substitution, working_values
    units.R              # convert_units
    validate.R           # check_required_columns, check_column_types,
                         #   type_matches, check_no_na, validation_abort
                         #   (generic validation kernel — added post-design)
    cache.R              # cache_dir, write_cache, read_cache, cached_ingest
                         #   (materialisation cache — added post-design)
    utils.R              # shared internal helpers (e.g. `%||%`)
  tests/testthat/        # ported from both repos' existing tests + new modules
  man/                   # roxygen
  .github/workflows/     # R-CMD-check.yaml (CI)
  renv/ + renv.lock      # pinned dependency environment
  README.md
  DESIGN.md              # this file
```

---

## 5. Migration plan

Each phase ends with **both repos' full test suites green**. Status as of
v0.4.3 (2026-06-24): ✅ done · ⬜ not started.

### Phase 0 — scaffold ✅
Create the `tritonIngest` repo (DESCRIPTION, package skeleton, roxygen, testthat).
GitHub: `shepherd70/tritonIngest`.

### Phase 1 — port the engine + utilities (no consumer touched) ✅
Move the functions in §2 into tritonIngest, refactored to take contract objects
(not role strings) and a parameterized profiles directory. Port the relevant
existing tests from both repos:
- from wq: `test-io_import.R`, `test-censored*.R` (parsing parts), unit tests.
- from bw: `test-data_contract.R`, `test-mapping_profiles.R`, `test-coerce_excel_date.R`.
Deliverable: tritonIngest standalone-green. **Zero changes to wq or bw yet.**

### Added beyond the original plan ✅
While standalone, the package also grew two domain-agnostic capabilities not in
the original §2 scope, plus project infrastructure:
- **`validate.R`** — a generic validation kernel (`check_*` → failure messages +
  `validation_abort`) for downstream packages (`tritonmr`, `electrocpue`, …).
  This is distinct from `validate_against_contract()`, which checks a frame
  against a contract object; the kernel is a lower-level check battery.
- **`cache.R`** — a materialisation cache for the post-ingestion canonical
  object (rds / parquet backends, source-fingerprint invalidation).
- CI (`R-CMD-check.yaml`) and a pinned `renv` environment.

### Phase 2 — migrate `bw-analysis-code` ✅
**Done** — `bwanalysis` imports `tritonIngest` and its `data_contract.R`,
`mapping_profiles.R`, and `coerce_excel_date.R` are thin role-based wrappers that
delegate to the shared engine (`DATA_CONTRACTS` stays local). Initial adoption
landed 2026-06-09 (tracker task 131); pin bumped to `v0.4.3` on 2026-06-24.

- Add `tritonIngest` to bw `Imports` (+ `Remotes`/renv git ref).
- Replace the bodies of bw `data_contract.R`/`mapping_profiles.R`/
  `coerce_excel_date.R` with re-exports or thin wrappers:
  - `auto_map(cols, role)` → `tritonIngest::auto_map(cols, DATA_CONTRACTS[[role]])`
  - keep `DATA_CONTRACTS` (domain) local.
- `mapping_profiles_dir()` → call shared with `here::here("data","processed","mapping_profiles")`.
- Run bw's suite + the Shiny explorer smoke path.

### Phase 3 — migrate `water-chemistry-qaqc` ⬜
- Add `tritonIngest` to wq `Imports`.
- Re-export `read_wq_file`→`read_tabular`, `detect_layout`, `melt_wide`,
  `parse_censored`, `apply_substitution`, `working_values`, `convert_units`
  from tritonIngest (keep the old names as aliases).
- Re-express `suggest_roles`/`assemble_wqdata`/`import_wq` on top of a
  `wq_contract()` + `auto_map()` + the shared censored parsing. `wqdata` model,
  guideline engine, stats, plots, Shiny stay local.
- Run wq's full suite (currently 315 tests).

### Phase 4 — the payoff: chemistry ingestion in bw ⬜
- Define a `chemistry`/`metals` contract in bw (analyte, value, units, censored,
  detection_limit, sample keys).
- Ingest bw's tissue-metals + sediment workbooks through tritonIngest's
  non-detect parsing + unit reconciliation — capability bw lacks today.

---

## 6. Distribution & versioning

- New public/private GitHub repo `shepherd70/tritonIngest`, semver tags
  (`v0.1.0` …).
- Consumers pin it: `DESCRIPTION` `Remotes: github::shepherd70/tritonIngest@v0.4.3`
  (current release) and the resolved ref recorded in each repo's `renv.lock`.
- Breaking changes to the shared API bump the minor version while both repos are
  pre-1.0; never force-push tags.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Two production repos depend on it → a bad change breaks both | Port first (Phase 1) with no consumer wired; migrate one repo at a time; keep both suites green at each phase; pin tags. |
| Contract-engine decoupling (role → object) changes bw call sites | Keep `role`-string wrappers in bw that resolve against its local `DATA_CONTRACTS`. No call-site edits required. |
| Name clashes / muscle memory (`read_wq_file`, `suggest_roles`) | Retain old names as deprecated aliases in each repo. |
| renv friction installing a git dep | Document the `renv::install("github::…")` + `renv::snapshot()` step in each repo's README. |
| Scope creep (stats/guidelines drifting into the shared pkg) | Hard rule in §2: plumbing only; anything needing NADA/EnvStats/ggplot/shiny is out. |

---

## 8. Open questions

1. **Repo visibility** — public or private GitHub? (affects install auth in renv/CI)
2. **`read_tabular` return contract** — keep wq's "everything as character" default
   (preserves `<DL` notation, lets `parse_censored` run), with opt-in typed read? (proposed: yes)
3. **Profiles location** — parameterize per call (proposed) vs a package option
   (`options(tritonIngest.profiles_dir=)`)?
4. **Do we fold `process_qaqc`'s generic bits in**, or leave all QC-rule logic in
   the consumers? (proposed: leave domain QC in consumers; only ingestion here)
5. **Minimum R version** — match the stricter of the two repos.
