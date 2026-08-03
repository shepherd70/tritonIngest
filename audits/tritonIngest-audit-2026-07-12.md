# tritonIngest — Full Technical Review (2026-07)

Dimensions run: correctness; architecture and API design; security and provenance;
maintainability and dependencies; R package conventions; pipeline robustness;
cross-repository portability; performance and caching; documentation/design
alignment; and an engineering assessment of R versus Python. Statistical validity
and regulatory-method review were not run because this repository intentionally
contains ingestion plumbing rather than analyses, estimators, or reporting logic.

## Executive Summary

`tritonIngest` has the right architectural center of gravity: a small R package of
domain-owned contracts plus domain-agnostic readers, structural cleanup, reshaping,
mapping, censored-value parsing, unit conversion, validation, profiles, and cache
primitives. The implementation is unusually candid about dangerous spreadsheet
behavior, and v0.6.0 closes most of the silent-corruption paths found in the July
pressure test. The function-level decomposition is coherent, dependencies are lean,
public functions are documented, CI spans Windows/macOS/Linux and multiple R
versions, and the current suite is substantial.

The package is not yet safe to treat as a fully trustworthy canonicalization layer.
The highest-risk residual defects are in caching: cache validity covers source bytes
but not the parser, parser arguments, contract, mapping profile, package version, or
backend-specific artifact. Targeted probes reproduced both stale transformation
reuse and RDS/parquet sidecar cross-contamination, each returning the wrong object as
a valid hit. Contract readiness also overstates data usability: an empty required
table is ready, sparse mostly-unparseable data can be `ok`, dates are not type-checked,
and warnings never make readiness false. On this Windows host, the advertised micro-
unit support fails under an ASCII native locale, producing two test failures and
`NA` conversions. Duplicate headers remain warnings followed by repair, even though
the pressure test demonstrated that repaired duplicates can swap analyte identity.

The engineering recommendation is **keep the ingestion engine in R and harden it;
do not perform a wholesale Python migration now**. Python offers excellent service,
CLI, cloud, typing, and schema ecosystems, but it does not remove the difficult
parts here: workbook forensics, ambiguous layout, raw-value preservation, censoring
semantics, and human-confirmed mappings. Reimplementing 44 exports and hundreds of
tests would create a second semantic authority while both current consumers remain
R packages. Use Python later at an operational boundary—upload service, queue
worker, CLI orchestration, or cloud execution—and exchange a versioned canonical
table plus manifest through Parquet/Arrow. Keep one conformance suite and one
authoritative ingestion implementation until service demand justifies a second.

## Strengths

- **Scope and cohesion are strong.** `DESCRIPTION:7-16` and `DESIGN.md:35-40`
  clearly exclude domain schemas, guideline logic, statistics, and plotting. The
  package accepts contract objects rather than reaching into consumer globals.
- **Raw-text preservation is the correct default.** `R/read.R:102-159` reads CSV,
  TSV, XLSX, and XLS as text by default, preserving leading zeros, non-detect
  notation, and mixed cell representations. This matches readxl's documented text
  coercion behavior and avoids fragile type guessing.
- **Recent hardening is technically meaningful.** Content signatures, strict date
  matching, right-censoring, qualifier extraction, duplicate-header warnings,
  hidden-sheet discovery, transposed-table handling, row checks, and opt-in fuzzy
  mapping directly address failures reproduced on real environmental files.
- **Function boundaries are mostly clean.** Reading, structural cleanup, layout
  inference, reshaping, contracts, profiles, censor parsing, units, validation, and
  caching live in separate modules with narrow responsibilities.
- **The contract ownership model is portable.** `cf_field()`/`as_contract()` take
  schemas as data, allowing chemistry and fish/effort/habitat consumers to retain
  domain vocabulary outside this package.
- **Fuzzy matching is now appropriately conservative.** `R/contract.R:79-102`
  defaults `max_distance` to zero and warns when fuzzy matching is explicitly
  enabled. This is the correct default for similar analyte names.
- **Censoring preserves direction and raw semantics.** `R/censored.R:61-190`
  distinguishes detected, left-censored, right-censored, missing, and unparseable
  values, and keeps detection limits separate from right-censor bounds.
- **Unit ladders avoid scientifically invalid cross-dimensional conversion.**
  `R/units.R:37-68` keeps mass/volume and mass/mass separate and warns on unresolved
  conversion rather than inventing a value.
- **Validation failures compose well.** The `check_*()` functions return messages
  and `validation_abort()` raises a classed condition carrying all failures, which is
  a useful cross-package kernel.
- **Packaging and CI are mature for a small internal package.** Roxygen-generated
  documentation and namespace are coherent; CI covers Windows, macOS, R release,
  devel, and oldrel (`.github/workflows/R-CMD-check.yaml:19-50`).
- **Security and provenance are clean after triage.** `git fsck` passed. The scanner's
  two critical candidates were standard `renv/activate.R` download branches; its 36
  medium candidates were benign prose containing “silently.” GitHub merge/deploy
  author/committer splits are expected, and co-author trailers are consistent.

## Issues & Risks

### Critical

- `R/cache.R:245-273` — **Cache validity ignores the transformation.**
  `cached_ingest()` checks only the cache key/backend and source fingerprint before
  returning. It does not fingerprint `parse`, `...`, the contract, mapping profile,
  package version, schema version, or external configuration. A probe called the
  same parser on the same source with `multiplier = 2` and then `multiplier = 10`;
  both calls returned `4`. A changed sheet, date format, header row, mapping, unit
  target, or censoring policy can therefore receive a plausible but obsolete object.
  Fix: define a deterministic transformation fingerprint over the parser identity,
  normalized arguments/configuration, contract/profile hashes, package version, and
  canonical-schema version; require it on reads and record it in metadata.

- `R/cache.R:100-107`, `R/cache.R:174-189`, `R/cache.R:207-241` — **RDS and
  Parquet artifacts share one metadata sidecar, and `read_cache()` does not validate
  the recorded backend.** Writing `key = "shared"` as RDS for source A and then as
  Parquet for source B overwrites `shared.cache.json`. A targeted read of the RDS
  against source B returned source A's old RDS object because the Parquet sidecar's
  fingerprint was accepted. Fix: use backend-specific metadata paths or one manifest
  containing independent artifact records; validate schema, key, format, source list,
  fingerprint method, transformation fingerprint, and artifact checksum before load.
  Write data and metadata atomically via temporary files and rename.

### Major

- `R/units.R:27-42` — **Microgram aliases are not portable to this Windows
  locale.** The suite produced two failures: both micro sign (`U+00B5`) and Greek mu
  (`U+03BC`) inputs returned `NA` instead of converting `1000 µg/L` to `1 mg/L`.
  Package build/install also warned that `µg/l`, `µg/kg`, and `µg/g` could not be
  translated under the ASCII session charset. Fix: normalize both code points to the
  ASCII token `u` using runtime code-point construction (`intToUtf8`) rather than
  embedding interpreted Unicode escapes as lookup-table names; test under forced
  non-UTF-8 Windows locales.

- `R/contract.R:277-318`, `R/contract.R:345-355` — **“Ready” means columns are
  present, not that required data are usable.** A zero-row frame with a required
  numeric column returns `TRUE`. A required column with some missing values is `ok`;
  `type_warn` is only a warning; and all warnings are compatible with readiness.
  Fix: define explicit readiness policies (`structure`, `ingest`, `strict`) and make
  the production policy require at least one row, required-cell completeness, no
  coercion loss beyond a configured threshold, and no unresolved error-grade checks.

- `R/contract.R:294-301` — **Sparse-column type validation uses the wrong
  denominator.** `n_bad / length(x)` includes `NA`s. The probe with 22 unparseable
  values and 115 `NA`s returned `ok`, even though 100% of populated values were bad.
  Fix: divide by the number of non-missing/non-blank values, report `n_bad/n_present`,
  and distinguish empty, sparse, partially invalid, and wholly invalid columns.

- `R/contract.R:266-318` — **Contract date types are never validated.** Only
  numeric/integer types enter the coercibility branch. A required `date` column of
  arbitrary strings can be `ok` and ready when validation is called before coercion;
  mixed failed date coercions can also pass after some rows parse. Fix: consolidate
  contract type validation with `type_matches()`/a single type registry and add
  element-level date parse accounting.

- `R/read.R:68-100`, `R/read.R:145-155`, `R/clean.R:201-224` — **Duplicate
  source headers are warned about, then ingestion continues with repaired names.**
  The July corpus proved a duplicated magnesium label that actually contained
  manganese in one position. Making names unique does not make their meaning safe;
  warnings are also routinely suppressed in report pipelines. Fix: default to an
  error/quarantine result when populated duplicate headers exist. Provide an explicit
  `duplicate_names = "error"|"warn"|"repair"` escape hatch and retain original name,
  position, and repair provenance.

- `R/contract.R:197-263` — **The mapping and censor-parsing APIs still compose
  unsafely by default.** `apply_column_map(coerce = TRUE)` can destroy `<DL`, `ND`,
  and `>UL` strings before `parse_censored()` runs. v0.6.0 warns, which is an
  improvement, but it still returns the lossy result. Fix: default canonical
  measurement fields to raw-character preservation; add a parser/coercer registry or
  a contract type such as `measurement_raw`; make lossy coercion an error in strict
  mode; never mutate away the source representation.

- `R/profiles.R:64-138`, `R/contract.R:221-233` — **Mapping profiles are not
  bound to a contract or source schema.** The JSON schema string is written but not
  validated on load; there is no contract hash, ordered source-header fingerprint,
  mapping version, or compatibility check. A stale optional mapping can simply be
  dropped when its source column is absent. Fix: version and validate the profile
  document, store contract and ordered-header fingerprints, return structured
  mismatch diagnostics, and require explicit re-approval when either changes.

- `R/censored.R:99-141` — **Bare right-censor tokens cannot receive a separate
  upper/quantitation limit.** `TNTC` always gets `censor_limit = NA`; the only input
  is named `detection_limit`, and the implementation correctly refuses to reinterpret
  that lower limit as an upper bound. This contradicts the module header's “unless
  supplied” wording and leaves a common laboratory form incomplete. Fix: add a
  separately named `censor_limit`/`upper_limit` input with length checks and conflict
  reporting; never overload `detection_limit`.

- `tests/testthat/` — **Coverage is broad at the unit level but weak at the
  pipeline and corpus level.** There is no committed golden corpus exercising the
  full `read -> clean -> detect/transpose/melt -> map -> parse -> validate -> cache`
  flow, and the five files that exposed the July root causes are represented only in
  an audit narrative. Four workbook tests skipped locally because `zip` was absent.
  Fix: commit minimized, de-identified fixtures for each failure class and golden
  canonical outputs; run full-path regression tests on all CI platforms and both
  cache backends.

- `DESIGN.md:3-8`, `DESIGN.md:48-69`, `README.md:74-88` — **Primary design and
  status documentation is stale and in one place unsafe.** Both still call v0.5.0
  current; `DESIGN.md:58` advertises `auto_map(max_distance = 2L)` although v0.6.0
  deliberately changed the safe default to zero; new worksheet, transposed-layout,
  row-validation, and right-censor APIs are missing from the design inventory.
  Fix: reconcile DESIGN/README with v0.6.0 before the next release and make the safe
  no-fuzzy example normative.

### Minor

- `R/read.R:254-263` — A `Date` input is treated as its underlying days-since-1970
  number and then reinterpreted as an Excel serial. `as.Date("2024-01-01")` became
  `1953-12-30` in a probe. Fix: return `Date` unchanged or reject unsupported classes.
- `R/contract.R:38-52` — `as_contract()` accepts a tibble with the four named
  columns without validating field uniqueness, allowed type values, scalar logical
  `required`, synonym shape, or description. Fix: centralize contract construction
  and validation; reject duplicate/blank fields and malformed list columns.
- `R/contract.R:221-240` — A mapping target absent from the contract fails with the
  base error `subscript out of bounds`, not a domain-specific diagnostic. Fix: validate
  mapping target names, uniqueness, and source-name ambiguity before selection.
- `R/layout.R:72-119` — Layout inference excludes only a small name-based set of
  numeric identifiers. Years, coordinates, numeric lab IDs, detection limits, and QC
  counters can still make a long table look wide. Fix: return confidence/evidence per
  column, support caller-declared id columns, and require confirmation below a margin.
- `R/layout.R:204-227` — `transpose_table()` validates named vectors but not index
  bounds, overlaps, duplicate output names across header/label vectors, or duplicate
  sample selections. Fix: validate the complete reshape specification up front.
- `R/validate.R:140-158` — `check_unique()` silently checks the subset of requested
  key columns that happen to exist. A missing key component can create false duplicate
  failures on a coarser key. Fix: either skip unless all key columns exist or return a
  clear “key incomplete” failure.
- `R/validate.R:175-200` — `check_range()` suppresses numeric-conversion failures and
  checks only successfully parsed values. This is reasonable when composed with a type
  check but unsafe alone. Fix: document that dependency or optionally report
  unparseable populated values.
- `R/units.R:39-43` — Common aliases such as `ppm`/`ppb` are absent even where their
  dimensional meaning is unambiguous for mass/mass; `to` is documented as scalar but
  not validated. Fix: maintain a small explicit alias table and reject non-scalar
  targets clearly.
- `R/cache.R:36-45`, `R/profiles.R:19-28` — The return value is documented as an
  absolute path but the input is returned without normalization. Fix the behavior or
  the documentation.
- `renv.lock` — The lock records runtime imports but omits `testthat`, `zip`, and
  `arrow`, so `renv::restore()` alone did not recreate a complete development/check
  environment. Fix: document snapshot policy and add a reproducible check profile or
  `Config/Needs/check` entries.

## Detailed Findings by Module / Function Group

### Architecture & API Design

The package is cohesive and correctly keeps consumer contracts outside the engine.
The chief architectural inconsistency is that there are two schema/type systems:
contract validation in `contract.R` and the generic validation kernel in
`validate.R`. They disagree on supported types (`logical` exists only in the generic
kernel), casing (`date` versus `Date`), and semantics (coercibility versus actual R
class). A single internal type registry should own construction, coercion,
validation, typed missing values, and diagnostics.

The public surface has grown from the design's initial primitives to 44 exports.
Most exports are defensible, but internal helpers could consolidate: profile/cache
slugging and directory resolution are duplicated; cache/profile JSON manifests need
the same versioned/atomic persistence utility; and blank/token normalization is
spread across modules. Consolidation should be internal and should not collapse the
clean external module boundaries.

The package is generic enough for both consumers at the plumbing level. Hidden
assumptions remain:

- layout vocabularies lean toward chemistry terms (`analyte`, `concentration`),
  though callers can override them;
- contract types omit logical, time, datetime, enum, and identifier semantics needed
  by effort/habitat/field sheets;
- unit conversion is chemistry-oriented and not a general unit algebra system;
- censor substitution is a policy operation, not pure parsing, and should remain an
  explicitly selected downstream step;
- “ready” currently assumes a non-error structural mapping is sufficient, which is
  not adequate for either chemistry or fish event tables.

These are extension points, not a reason to put domain schemas into the package.

### Reading and Dates

`read_tabular()` has a sound all-text default, clear dispatch, and a valuable
signature check. Its format override is appropriately explicit. Worksheet discovery
and visibility recovery are useful additions. Remaining priorities are fail-closed
duplicate headers, a first-class read manifest (file, content type, sheet, visibility,
row/column counts, original names), and clearer behavior for empty files and
unsupported workbook containers.

`coerce_excel_date()` correctly avoids base R's prefix-match trap and refuses to
guess day/month order. The origin and serial-range controls are appropriate because
the 1900/1904 system and bare-year ambiguity cannot be inferred reliably from values
alone. It should additionally validate argument lengths/order, preserve an existing
`Date`, and return row-level parse diagnostics rather than only a warning when used in
production ingestion.

### Structural Cleaning and Layout

Blank-row/column stripping is simple and readable. `clean_table()` explicitly avoids
domain filtering and offers multi-row headers and label-row removal. That separation
is correct. Repeated paginated headers and richer metadata rows remain consumer- or
pipeline-level concerns, but the engine should expose provenance (`source_row`,
promoted header rows, repairs performed) so consumers can quarantine rather than
silently discard them.

Layout detection is necessarily heuristic. Returning a reason is good, but a single
categorical answer is too authoritative for ambiguous sheets. A future result should
include scores, evidence, candidate measure/id columns, and an `ambiguous` state.
`melt_wide()` safely reserves output names and preserves raw result text.
`transpose_table()` is useful but currently closer to a low-level reshaper than a
validated ingestion primitive; its index specification needs comprehensive checks.

### Schema Contracts and Mapping

Passing contracts as data is the strongest API decision in the repository. Exact and
synonym matching before opt-in fuzzy matching is also correct. However, contract
construction is permissive, mapping profiles lack compatibility identity, and
readiness is not a sufficient quality gate. The engine needs a versioned contract
object with:

- unique field names and a unified type registry;
- required-column and required-cell policies;
- raw versus derived field roles;
- optional enum/range/unique-key constraints supplied as data;
- a deterministic contract fingerprint;
- structured mapping provenance (`exact`, `synonym`, `fuzzy`, `manual`, distance,
  source position, ambiguity);
- strict readiness that can fail on warnings selected by policy.

Fuzzy matching should remain disabled by default and should never be auto-approved.

### Mapping Profiles

Human-approved JSON profiles are a good fit for recurrent lab formats. They should be
treated as versioned compatibility artifacts rather than name-to-name dictionaries.
Store the ordered raw header, source/vendor hints, contract version/hash, mapping
method, approval timestamp/actor, and optional fixture hash. Loading should validate
the document schema and return explicit stale/incompatible states. Writes should be
atomic. This keeps mappings reusable without letting an old workbook shape inherit a
plausible but incorrect map.

### Censored Values and Units

`parse_censored()` is one of the better parts of the engine. It retains raw parsing
semantics, distinguishes left/right censoring, avoids partial numeric rescue from
narrative cells, and extracts qualifiers. Add a separate supplied upper-limit vector,
validate negative/impossible limits, and consider returning a stable parse-status enum
instead of free-text `parse_note` as the machine interface.

`apply_substitution()` and `working_values()` are deliberately simple, but they
produce analysis working values and therefore encode policy. Keep them explicit,
never overwrite `value_raw`, record method/fraction in output metadata, and avoid
calling substituted right-censor bounds “measurements.”

`convert_units()` is intentionally narrow, which is preferable to pretending to be a
full units library. Fix Windows Unicode handling first, then add explicit aliases and
machine-readable conversion diagnostics. Do not add density-dependent conversions or
analyte-specific bases here.

### Generic Validation

The collect-all-errors interface is useful and domain-agnostic. Consolidate it with
contract validation and add a structured result class containing check id, severity,
column/key, row indices, examples, and message. Strings can remain the display layer.
Make missing key components explicit, and let consumers choose severity policies.
Domain bounds and keys should continue to be passed in, never hardcoded.

### Caching and Performance

The current performance strategy is sensible in outline: RDS for exact R object
round-trips and Parquet for a plain cross-language canonical table. MD5 provides
strong source invalidation; `size_mtime` is a documented lower-cost tradeoff. The
dominant bottlenecks are likely XLSX/XML reading, full-file MD5 on very large inputs,
wide-to-long materialization, and repeated string normalization—not ordinary dplyr
overhead.

Correctness must precede cache benchmarking. Introduce a manifest v2 with source
content hashes, ordered normalized source paths, transformation/config hash,
contract/profile hashes, package and R versions, backend, artifact checksum, schema
version, and row/column counts. Use atomic writes and a lock for concurrent workers.
After correctness, benchmark:

- MD5 versus size/mtime and optional two-stage fingerprinting;
- RDS compression modes versus Parquet compression/row-group sizes;
- cold workbook parse, reshape, validation, cache write, and warm read separately;
- representative narrow field sheets and very wide chemistry matrices;
- memory peak as well as elapsed time.

Parquet should be considered a materialized canonical artifact, not merely another
cache encoding. Its schema and manifest should be stable enough for Python/R
interchange; RDS should remain disposable and R-version-coupled.

### Tests, Documentation, and Package Maintenance

Independent local test result: **317 pass, 2 fail, 5 warnings, 4 skip**. The two
failures are the Windows micro-unit bug. The four skips are workbook tests gated on
`zip`. Package build/install emitted the same Unicode translation warnings. A fully
clean local `R CMD check` was not independently obtained because the isolated check
environment lacked optional `arrow`, and the host's forced ASCII locale then aborted
at the DESCRIPTION metadata subprocess; CI configuration itself is strong.

Unit tests cover every main module and many adversarial cases. Missing coverage is
primarily end-to-end, corpus/golden, cache-configuration invalidation, corrupted
manifests/profiles, concurrent writes, non-UTF-8 locales, and cross-language Parquet
schema fidelity. DESIGN and README must be reconciled with v0.6.0.

## Recommended Improvements

1. **Stop cache false hits before any new feature work.** Ship a cache manifest v2,
   backend-specific artifacts, transformation fingerprints, atomic writes, and
   regression tests for changed `...`, parser, contract, profile, backend, and source.
2. **Make ingestion fail closed.** Error by default on populated duplicate headers,
   invalid contract definitions, lossy strict coercion, and incompatible mapping
   profiles. Preserve a deliberate override for interactive recovery.
3. **Unify contract and validation semantics.** One type registry and one structured
   diagnostics model should serve coercion, typed NA completion, validation, and
   readiness.
4. **Redefine readiness.** Add row-count, required-cell, parse-loss, ambiguity, and
   warning policies. Make strict readiness the default for cached canonical output.
5. **Preserve provenance everywhere.** Carry source file/sheet/row, original column
   name/position, mapping method, raw value, parser status, and transformation version.
6. **Fix Windows Unicode unit handling and add locale CI.** This is a release blocker
   because current behavior returns `NA` for a supported environmental unit.
7. **Build a de-identified golden corpus.** Minimize each real failure into small
   CSV/XLSX fixtures and assert canonical tables plus manifests.
8. **Reconcile documentation and dependency restoration.** Update v0.6.0 API/status,
   remove the unsafe fuzzy example, and make check dependencies reproducible.
9. **Benchmark only after cache correctness.** Optimize measured XLSX/reshape/hash
   bottlenecks; do not migrate languages for speculative performance.

## Refactor Plan

### Stage 0 — Release blockers (1–2 weeks)

- Fix Unicode unit normalization and add Windows non-UTF-8 tests.
- Change duplicate-header default to error/quarantine.
- Correct sparse type denominators, date validation, and zero-row readiness.
- Add regression tests for the two reproduced cache failures; temporarily document
  cache keys as configuration-sensitive until manifest v2 lands.
- Reconcile DESIGN.md and README.md to v0.6.0.

### Stage 1 — Contract/validation kernel (2–3 weeks)

- Introduce an internal type registry for character, numeric, integer, logical, date,
  datetime, and time; leave enum values and bounds as caller-supplied constraints.
- Validate and fingerprint contract objects.
- Return structured diagnostics with display methods.
- Add readiness policies and strict canonical-output gating.
- Make raw measurement preservation explicit in contracts/mapping.

### Stage 2 — Profiles and cache manifest v2 (2–3 weeks)

- Version profile documents and bind them to contract/header fingerprints.
- Create one atomic JSON-manifest utility shared internally by profiles and cache.
- Separate RDS/Parquet artifact metadata and add artifact checksums.
- Fingerprint parser/configuration/package/schema identity.
- Add concurrent-writer locks and corruption recovery behavior.

### Stage 3 — Golden pipeline suite (2 weeks)

- Add minimized fixtures for mislabeled extension, duplicate analyte header, day-first
  date, 1904 dates, repeated/multi-row headers, transposed sheets, qualifiers,
  left/right censoring, QC/metadata rows, and changing detection limits.
- Assert full canonical outputs and provenance manifests.
- Run on all CI OS/R matrix entries, with RDS and Parquet jobs.
- Add a cross-repository compatibility job against pinned chemistry and bw consumers.

### Stage 4 — Performance and API stabilization (1–2 weeks)

- Benchmark cold/warm paths and memory on representative shapes.
- Optimize only observed bottlenecks.
- Mark the canonical schema/manifest as versioned and publish compatibility rules.
- Cut a pre-1.0 release, pin both consumers, and require both suites green before tag.

## Task 2 — R vs Python Assessment

### Pros of staying in R

- Both production consumers and their analysts are already in R, so contracts,
  conditions, tibbles, dates, and tests cross no runtime boundary.
- The engine already has 44 exports, 317 passing local assertions, real-workbook
  pressure-test history, roxygen docs, pkgdown, renv, and multi-OS R CI.
- readxl explicitly supports forcing all Excel columns to text, including converting
  Excel date cells to their underlying serial representation—the exact preservation
  strategy used here ([readxl documentation](https://readxl.tidyverse.org/reference/read_excel.html),
  [cell/column types](https://readxl.tidyverse.org/articles/cell-and-column-types.html)).
- readr supplies explicit character column specifications and parse-problem machinery
  for delimited files ([readr documentation](https://readr.tidyverse.org/reference/read_delim.html)).
- `renv` records exact package versions and restores isolated project libraries, which
  is adequate once check dependencies are included
  ([renv documentation](https://rstudio.github.io/renv/)).
- Keeping one language avoids semantic drift in date origins, NA/None behavior,
  integer coercion, Unicode, censor flags, categorical fields, and warning/error
  policy.
- The typical environmental workbook is modest enough that parser correctness and
  human mapping review dominate CPU performance.

### Cons of staying in R

- R is less natural than Python for standalone services, queue workers, containerized
  upload APIs, and broad enterprise automation.
- R package deployment to non-R operators can be less familiar, and Arrow is a heavy
  optional binary dependency.
- Static typing and typed configuration models are weaker than Python's mainstream
  tooling; this repository currently compensates with runtime contracts.
- Some workbook forensics—formula XML, styles, merged cells, VBA preservation, remote
  object stores—may require lower-level tooling beyond readxl.
- Windows locale behavior, demonstrated here, needs deliberate CI coverage.

### Pros of migrating to Python

- `pandas.read_excel()` supports sheet selection, dtype/converters, multiple engines,
  remote storage, and modern nullable backends
  ([pandas documentation](https://pandas.pydata.org/docs/reference/api/pandas.read_excel.html)).
- openpyxl exposes workbook structure at a lower level, including formula-versus-
  cached-value behavior, useful for difficult Excel forensics
  ([openpyxl documentation](https://openpyxl.readthedocs.io/en/stable/optimized.html)).
- Pandera provides strict schemas, coercion, uniqueness, ordered columns, parsers,
  lazy error collection, and multiple dataframe backends
  ([Pandera schemas](https://pandera.readthedocs.io/en/latest/dataframe_schemas.html)).
- Python is a stronger operational host for CLIs, web upload tools, background workers,
  object storage, observability, and container/cloud deployment. Modern packaging uses
  `pyproject.toml`, sdists, and wheels
  ([PyPA packaging guide](https://packaging.python.org/en/latest/tutorials/packaging-projects/)).
- PyArrow's native multithreaded Parquet implementation integrates with pandas and is
  well suited to canonical interchange
  ([PyArrow Parquet documentation](https://arrow.apache.org/docs/python/parquet.html)).

### Cons of migrating to Python

- It is a rewrite, not a port. Every warning, NA rule, date ambiguity, header repair,
  mapping priority, qualifier regex, and readiness policy must be specified and
  proven equivalent.
- Python's richer libraries do not solve semantic ambiguity: `Analyte = Effluent`,
  duplicate Mg/Mn headers, permit-limit rows, 1900/1904 origins, and `TNTC` limits
  still need explicit domain-owned contracts and human review.
- Pandas/openpyxl defaults differ from readxl/readr; date, formula, missing-value,
  dtype, and duplicate-name behavior can change canonical outputs.
- Downstream R packages would add Python environment provisioning, reticulate or
  subprocess failure modes, and cross-language type conversions. Reticulate can
  declare managed Python dependencies and convert pandas objects, but that is another
  environment to support
  ([reticulate package guidance](https://rstudio.github.io/reticulate/articles/package.html)).
- Two implementations during migration double the conformance burden and invite
  divergent bug fixes.
- A Python rewrite does not fix the current cache/contract specification gaps; it can
  faithfully reproduce them unless the semantics are redesigned first.

### Decision Summary (engineering-driven)

**Stay in R for the authoritative ingestion engine for at least the next release
cycle.** First harden cache identity, contract/readiness semantics, duplicate-header
handling, Unicode units, and golden regression coverage. These are specification and
correctness problems, not language limitations.

Adopt Python only when a concrete operational requirement exists—such as a hosted
self-serve uploader, event-driven cloud worker, or organization-wide CLI—and place it
outside the R analysis packages. At that point choose one of two patterns:

1. Python orchestrates and invokes the authoritative R engine in a container/process;
   or
2. Python implements ingestion behind the same versioned canonical schema and must
   pass the shared golden conformance suite before it can publish artifacts.

Parquet/Arrow is the appropriate typed table boundary. Both R Arrow and PyArrow read
and write Parquet ([Arrow R](https://arrow.apache.org/docs/r/reference/write_parquet.html),
[PyArrow](https://arrow.apache.org/docs/python/parquet.html)). Pair every Parquet file
with a JSON manifest because Parquet alone does not capture mapping approval,
source-row provenance, transformation identity, or validation policy.

## Task 3 — R to Python Transition Plan

### Executive Summary

A full R-to-Python migration is **not recommended**, so the requested 12-week
transition program should not be activated now. The near-term refactor plan above
delivers more risk reduction at much lower cost while preserving both downstream R
workflows.

### Migration Rationale

The trigger for migration should be operational, not aesthetic: sustained demand for
cloud workers, a self-serve upload service, organization-wide non-R clients, or data
volumes/latency that measured R optimization cannot meet. Before that decision, the R
engine must define a stable canonical schema, manifest, and golden corpus; otherwise
there is no precise target to migrate.

### Conditional Python Architecture Overview

If those triggers are met later:

```text
raw CSV/XLS/XLSX
        |
Python ingestion service / CLI
        |
        +-- canonical.parquet
        +-- canonical.manifest.json
        +-- validation.json
        |
R consumer package -> Arrow read -> schema/manifest check -> existing analysis
```

The manifest must include source hashes, source file/sheet/row provenance, ordered
original headers, mapping/profile id and approval, contract/schema version, parser
version/configuration, censor parse status, units policy, artifact checksum, and
validation results.

### Conditional Module Mapping

| R primitive | Future Python module/function | Likely foundation |
|---|---|---|
| `read_tabular`, `sniff_format` | `io.read_tabular`, `io.sniff_format` | `pathlib`, magic-byte checks, pandas/openpyxl |
| `list_sheets`, `read_all_sheets` | `excel.list_sheets`, `excel.read_sheets` | openpyxl workbook metadata |
| `coerce_excel_date` | `dates.coerce_excel_date` | `datetime`, explicit 1900/1904 origin, regex/full parse |
| `clean_table`, blank/label drops | `clean.clean_table`, `clean.drop_*` | pandas string-preserving transforms |
| `find_header_row` | `clean.find_header_row` | scored heuristic with evidence |
| `detect_layout`, `looks_transposed` | `layout.detect_layout` | scored classifier, explicit ambiguity |
| `melt_wide`, `transpose_table` | `layout.melt_wide`, `layout.transpose_table` | pandas melt/stack |
| `cf_field`, `as_contract` | `contracts.Field`, `contracts.Contract` | dataclasses/Pydantic; optional Pandera projection |
| `auto_map` | `mapping.auto_map` | normalized exact/synonym matching; RapidFuzz opt-in |
| `apply_column_map` | `mapping.apply_column_map` | raw-preserving pandas selection/rename |
| contract validation/readiness | `contracts.validate`, `contracts.is_ready` | Pandera plus custom structured diagnostics |
| profile save/load | `profiles.save`, `profiles.load` | versioned Pydantic JSON model, atomic writes |
| `parse_censored` | `measurements.parse_censored` | compiled regex/vectorized string operations |
| substitution/working values | `measurements.working_values` | explicit policy module, never overwrite raw |
| `convert_units` | `units.convert` | explicit aliases or Pint with locked registry |
| generic `check_*` | `validation.check_*` | structured issue objects/Pandera checks |
| cache functions | `cache.ManifestCache` | SHA-256/BLAKE3, atomic files, locks, PyArrow |

### 12-Week Migration Roadmap

**Not scheduled.** If the trigger is approved later, use this gate-based sequence:

- Weeks 1–2: freeze canonical schema/manifest v1 and golden corpus in R.
- Weeks 3–5: build a parallel Python prototype for read/clean/layout/date/censor paths;
  publish no production artifacts.
- Weeks 6–7: implement contracts, profiles, strict validation, and cache manifests;
  require golden equivalence.
- Weeks 8–9: integrate one read-only pilot in chemistry, with R remaining fallback and
  source of truth.
- Weeks 10–11: pilot fish/effort/habitat and exercise Parquet/manifest consumption in
  both R packages.
- Week 12: decide go/no-go from equivalence, operations, analyst usability, latency,
  and incident-recovery evidence. Do not deprecate R until two release cycles pass.

### Testing & Validation Plan

- Golden raw files and canonical Parquet/JSON outputs, including every known failure.
- Property tests for censor strings, date formats, headers, name normalization, and
  mapping uniqueness.
- Cross-language equality on values, nulls, dates/time zones, column order/types,
  qualifiers, provenance, issue severities, and artifact hashes.
- Mutation tests that alter one source byte, parser option, contract, profile, package
  version, or backend and require cache invalidation.
- Consumer contract tests in chemistry and bw repositories on every release candidate.
- Performance tests on realistic narrow and wide sheets; no performance acceptance
  claim without cold/warm and memory measurements.

### Rollout Plan for Downstream R Packages

- Keep existing R ingestion wrappers and signatures.
- Add a provider setting (`r` default, `python` pilot) behind those wrappers.
- Python writes versioned Parquet plus manifest; R reads with Arrow and validates the
  schema/manifest before constructing existing R domain objects.
- On any provider failure or schema mismatch, fail closed and allow an explicit
  operator fallback to the R path; never silently switch within a production run.
- Pin the Python wheel/container digest and R consumer release together.
- Preserve the R engine for at least two stable releases and one full annual data
  cycle before considering deprecation.

### Risks & Mitigations

| Risk | Mitigation |
|---|---|
| R/Python semantic drift | One golden corpus, one canonical spec, cross-language tests |
| Analyst disruption | Existing R wrappers and R objects remain unchanged |
| Environment complexity | Pinned wheel/container; manifest records versions/digests |
| Null/date/category mismatch | Explicit Arrow schema and equality tests |
| Workbook edge regression | Minimized fixtures from every real incident |
| Split bug fixes | One implementation remains authoritative until cutover gate |
| Cache false hits | Transformation-aware manifest and mutation tests |
| Rollback difficulty | Provider flag, retained R path, immutable source/artifacts |

### Long-Term Maintenance Strategy

Own the canonical schema, manifest, and corpus as language-neutral specifications.
Assign one team/release process to both bindings. Require semver, changelogs, signed or
immutable artifacts where appropriate, dependency lockfiles, SBOM/security scanning,
and compatibility matrices. Prefer one authoritative implementation; maintain two only
when independent operational value outweighs permanent conformance cost.

## Task 4 — Final Recommendation

Use a **clean coexistence model**:

- **R remains the analysis language and the authoritative ingestion implementation
  now.** Fix the release blockers and complete chemistry adoption before introducing a
  second engine.
- **Python may own orchestration and services later.** Use it for upload APIs, queue
  workers, cloud scheduling, CLI distribution, and integrations where Python has a
  clear operational advantage.
- **Parquet plus a versioned JSON manifest is the boundary.** Feather/Arrow IPC is
  suitable for ephemeral local exchange, but Parquet is the better durable artifact;
  neither replaces the provenance/validation manifest.
- **Do not call Python from every analyst's R session unless necessary.** A produced
  artifact boundary is easier to pin, audit, retry, and reproduce than an embedded
  mixed-runtime call. Reticulate remains a valid transitional adapter, not the default
  production architecture.
- **Do not deprecate the R layer on a calendar alone.** Require golden equivalence,
  both consumer suites green, two stable releases, one annual environmental-data
  cycle, documented rollback, and operational ownership.

## Next Steps for the Maintainer

1. Treat both cache findings and the Windows unit failure as release blockers.
2. Open focused issues for strict readiness/type validation, duplicate-header failure,
   profile compatibility, bare right-censor limits, golden fixtures, and doc drift.
3. Implement Stage 0 on a fix branch; add tests before changing behavior.
4. Run the full local/CI matrix with `testthat`, `zip`, and `arrow` reproducibly
   installed; verify Windows non-UTF-8 behavior explicitly.
5. Release a hardened R version and update both consumer pins.
6. Finish `water-chemistry-qaqc` migration and chemistry-in-bw work using the hardened
   R engine.
7. Revisit Python only when a concrete service/automation requirement has an owner,
   budget, SLO, and measured benefit.

## Could Not Verify

- The supplied repository contains no raw pressure-test workbooks, so the July
  per-file claims could not be replayed from this checkout.
- The downstream `water-chemistry-qaqc` and `bw-analysis-code` repositories were not
  in scope for this single-repository audit, so current wrapper/API compatibility and
  their complete test suites were not independently rerun.
- A fully clean local `R CMD check` was not obtained on this host for the environment
  reasons described above; CI configuration and prior history report clean checks,
  but that is not equivalent to current independent verification.
- No representative large-file corpus was present, so performance conclusions are
  architectural rather than benchmark measurements.
