# tritonIngest developer handoff

- Last verified: 2026-08-27
- Baseline: `main` at `317e7fb`
- Package version: `0.7.1`
- Latest release: `v0.7.1`, published 2026-07-14
- Maintainer: Travis Shepherd (`travis.shepherd@tritonenv.com`)
- License: MIT

## Read this first

`tritonIngest` is the shared, domain-agnostic R ingestion engine for
messy field and laboratory tables. It reads CSV, TSV, XLS, and XLSX
sources without discarding fragile source notation, recovers table
structure, maps columns to consumer-owned contracts, parses censored
values, validates canonical data, and can emit verified cache or
Arrow-based interchange artifacts.

The package is deliberately plumbing only. Fish biology, chemistry
guideline logic, project schemas, statistics, plots, and reporting
belong in consuming repositories. Preserve that boundary: a feature that
needs to know a species, analyte list, permit, station, or project
workflow probably does not belong here.

The package is mature enough to be an authoritative R canonicalizer, but
several coordination tasks remain. In particular, the primary design and
status documentation is stale, downstream consumers pin different
historical releases, and the active backlog has not been converted into
GitHub issues. Those are the best places for the next developer to
start.

The July audit documents are historical snapshots, not a current defect
list. Releases `0.7.0` and `0.7.1` fixed the audit’s highest-risk
findings, including transformation-aware cache validation,
backend-specific cache manifests, strict contract readiness, fail-closed
duplicate headers and coercion, mapping profile fingerprints, Unicode
censor operators, and formula provenance. Check `NEWS.md` and the
current implementation before reopening an audit finding.

## Repository state at handoff

- `main` and `origin/main` are synchronized at `317e7fb`.
- `v0.7.1` points to `795a520`. The four commits after the tag add an
  audit, improve real-workbook instructions, normalize lockfile line
  endings, and fix README wording; they do not change package behavior.
- There were no open GitHub issues or pull requests when this handoff
  was verified.
- The latest R-CMD-check run for `317e7fb` passed on macOS release,
  Windows release, and Ubuntu devel/release/oldrel-1.
- The latest pkgdown build and GitHub Pages deployment also passed. The
  published site is <https://shepherd70.github.io/tritonIngest/>.
- The public namespace contains 50 exported functions.
- The suite contains 132 `test_that()` cases. Four secure real-workbook
  cases are opt-in, the shared-spec case requires an environment
  variable, and optional `arrow`/`zip` paths can skip when their
  dependency is unavailable.
- `README.md` still says “v0.7.1 development” even though `v0.7.1` is
  released. `DESIGN.md` also has stale API, migration, and
  release-status details; see [Recommended next
  work](#recommended-next-work).

The canonical Git remote is:

``` text
https://github.com/shepherd70/tritonIngest.git
```

## First-time setup

### Requirements

- R 4.2 or newer. `renv.lock` was generated with R 4.6.0.
- Git and network access for the public GitHub dependency/specification
  repos.
- A compiler toolchain for any source packages required on the target R
  platform.
- Pandoc for package and pkgdown checks.
- Python with `openpyxl` only when running the independent
  secure-workbook comparison.

The repository uses `renv` and its `.Rprofile` activates the project
library. From the repository root:

``` r

renv::restore()
```

The lockfile captures runtime imports, but it does not provide a
complete development/check environment. Install the development tools
and lightweight suggested dependency explicitly:

``` r

renv::install(c("testthat", "pkgload", "roxygen2", "rcmdcheck", "zip"))
```

Install `arrow` when exercising Parquet, Feather, cache, or
canonical-bundle paths:

``` r

renv::install("arrow")
```

At handoff, this machine’s project library contained only `renv`. The
global library contained development tools but had `tritonIngest` 0.7.0
installed, while the source tree is 0.7.1. Restore the project library
before treating a local test result as evidence; otherwise `pkgload` or
a subprocess can accidentally exercise the wrong installed version.

Useful environment checks are:

``` r

.libPaths()
renv::status()
packageVersion("tritonIngest")
```

### Run tests and package checks

After restoring the environment:

``` r

pkgload::load_all()
testthat::test_local()
rcmdcheck::rcmdcheck(args = c("--no-manual"), error_on = "warning")
```

CI also checks conformance against release 1.0.0 of
`shepherd70/tabular-ingestion-spec`. To reproduce that test locally,
check out the tag and point the suite at it:

``` bash
git clone --branch v1.0.0 --depth 1 \
  https://github.com/shepherd70/tabular-ingestion-spec.git \
  ../tabular-ingestion-spec
export TABULAR_INGESTION_SPEC_DIR="$PWD/../tabular-ingestion-spec"
Rscript -e "pkgload::load_all(); testthat::test_file('tests/testthat/test-shared-spec.R')"
```

The CI workflow performs the equivalent checkout into `.spec/` and sets
`TABULAR_INGESTION_SPEC_DIR` automatically.

Private workbooks are intentionally absent from Git. Follow
[tests/REAL-WORKBOOK-VALIDATION.md](https://shepherd70.github.io/tritonIngest/tests/REAL-WORKBOOK-VALIDATION.md)
to run the opt-in secure-workbook checks. Never replace the stored
baseline merely to make a test pass; a changed source checksum requires
manual review and recorded approval.

## What the package does

The main data flow is:

``` text
CSV / TSV / XLS / XLSX
          |
          v
sniff_format() -> read_tabular() / read_all_sheets()
          |          |
          |          +--> list_sheets() / inspect_workbook()
          v
clean_table() -> detect_layout() -> transpose_table() / melt_wide()
          |
          v
consumer-owned contract -> auto_map() -> apply_column_map()
          |                                  |
          |                                  v
          +----------------> parse censored values / normalize units
                                             |
                                             v
                          validate_against_contract()
                          + generic check_*() battery
                                             |
                                             v
                 cache v2 / canonical bundle v1 / diagnostics v1
                                             |
                                             v
                              domain-specific consumers
```

### Reading and workbook provenance

[`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md)
reads columns as text by default so leading zeroes, non-detect notation,
qualifiers, and mixed representations survive ingestion.
[`sniff_format()`](https://shepherd70.github.io/tritonIngest/reference/sniff_format.md)
checks the file signature instead of trusting the extension. For
workbooks,
[`list_sheets()`](https://shepherd70.github.io/tritonIngest/reference/list_sheets.md)
includes `hidden` and `veryHidden` sheets, while
[`inspect_workbook()`](https://shepherd70.github.io/tritonIngest/reference/inspect_workbook.md)
inventories formula cells, formulas missing cached results, merged
ranges, visibility, and sheet identity.

Excel readers consume cached formula results rather than calculating
formulas. The `formula_policy` argument is therefore a review gate, not
a calculation engine:

- `"warn"` is the default and carries structured provenance diagnostics.
- `"error"` rejects formula-bearing input.
- `"allow"` is an explicit acceptance of the risk.

### Structural cleanup and layout

[`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md)
can recover one- or multi-row headers, strip blank rows/columns, remove
label rows, and preserve ingestion diagnostics.
[`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md)
distinguishes long, wide, and transposed layouts;
[`melt_wide()`](https://shepherd70.github.io/tritonIngest/reference/melt_wide.md)
and
[`transpose_table()`](https://shepherd70.github.io/tritonIngest/reference/transpose_table.md)
perform the corresponding reshapes.

Layout detection is a heuristic. Treat its reason/evidence as a
suggestion, especially when numeric identifiers, coordinates, detection
limits, or QC counters resemble measurement columns. Consumer code
should make ambiguous layout decisions reviewable instead of silently
accepting them.

### Contracts and mapping

Consumers declare schemas with
[`cf_field()`](https://shepherd70.github.io/tritonIngest/reference/cf_field.md)
and
[`as_contract()`](https://shepherd70.github.io/tritonIngest/reference/as_contract.md).
Supported field types are `character`, `numeric`, `integer`, `logical`,
`date`, `datetime`, and `time`. The contract is passed into the engine;
it is never a package-global domain registry.

[`auto_map()`](https://shepherd70.github.io/tritonIngest/reference/auto_map.md)
matches exact canonical names first, then synonyms. Fuzzy matching is
opt-in: `max_distance = 0` is the safe default. When fuzzy matching is
enabled, every fuzzy result must be reviewed.

[`apply_column_map()`](https://shepherd70.github.io/tritonIngest/reference/apply_column_map.md)
selects, renames, and optionally coerces mapped columns. Its default
loss policy is `"error"`. Parse raw measurement text before numeric
coercion so `"<0.25"`, `"ND"`, and `">2420"` are not destroyed.

[`validate_against_contract()`](https://shepherd70.github.io/tritonIngest/reference/validate_against_contract.md)
is strict by default and reports field presence, population,
missingness, invalid counts, and severity.
[`contract_is_ready()`](https://shepherd70.github.io/tritonIngest/reference/contract_is_ready.md)
requires at least one row and treats warning-grade results as not ready
by default. The lower-level `check_*()` functions compose
domain-agnostic record checks before
[`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md)
raises one classed error containing all failures.

### Censoring and units

[`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md)
keeps detected, left-censored, right-censored, missing, and unparseable
values distinct. Detection limits are not upper censor bounds. When
substitution is an approved downstream policy, pass censor direction and
limits explicitly or call
[`working_values()`](https://shepherd70.github.io/tritonIngest/reference/working_values.md)
with the complete parsed tibble.

[`convert_units()`](https://shepherd70.github.io/tritonIngest/reference/convert_units.md)
supports separate mass/volume and mass/mass ladders and never crosses
between them without a scientifically valid conversion. Unsupported
non-identity conversions return `NA` with a warning; they are not
guesses.

### Cache and canonical artifacts

Cache v2 verifies the data checksum, key, backend, source fingerprint,
and transformation fingerprint. Custom parsers must supply a
transformation context containing `parser_id`, `parser_version`, and
`schema_version`. Changed parser arguments, contracts, profiles, sheets,
or configuration should be represented in that context so stale output
becomes a cache miss.

Canonical bundles require `arrow`. They contain one Parquet or Feather
table, a diagnostics document, and a manifest recording source identity,
checksums, engine/spec versions, the contract fingerprint,
transformation identity, row count, and column count.
[`read_canonical_bundle()`](https://shepherd70.github.io/tritonIngest/reference/read_canonical_bundle.md)
verifies contained artifact checksums and can also verify current source
files.

## Public API

| Area | Exported functions | Notes |
|----|----|----|
| Reading and dates | [`sniff_format()`](https://shepherd70.github.io/tritonIngest/reference/sniff_format.md), [`read_tabular()`](https://shepherd70.github.io/tritonIngest/reference/read_tabular.md), [`coerce_excel_date()`](https://shepherd70.github.io/tritonIngest/reference/coerce_excel_date.md) | Reads CSV/TSV/XLS/XLSX as text by default and verifies content type. |
| Workbook inspection | [`list_sheets()`](https://shepherd70.github.io/tritonIngest/reference/list_sheets.md), [`read_all_sheets()`](https://shepherd70.github.io/tritonIngest/reference/read_all_sheets.md), [`inspect_workbook()`](https://shepherd70.github.io/tritonIngest/reference/inspect_workbook.md) | Includes hidden-sheet and formula provenance. |
| Structural cleanup | [`find_header_row()`](https://shepherd70.github.io/tritonIngest/reference/find_header_row.md), [`clean_table()`](https://shepherd70.github.io/tritonIngest/reference/clean_table.md), [`drop_blank_rows()`](https://shepherd70.github.io/tritonIngest/reference/drop_blank_rows.md), [`drop_blank_cols()`](https://shepherd70.github.io/tritonIngest/reference/drop_blank_cols.md), [`drop_label_rows()`](https://shepherd70.github.io/tritonIngest/reference/drop_label_rows.md) | Diagnostics survive supported cleanup paths. |
| Layout and reshape | [`is_value_like()`](https://shepherd70.github.io/tritonIngest/reference/is_value_like.md), [`detect_layout()`](https://shepherd70.github.io/tritonIngest/reference/detect_layout.md), [`looks_transposed()`](https://shepherd70.github.io/tritonIngest/reference/looks_transposed.md), [`melt_wide()`](https://shepherd70.github.io/tritonIngest/reference/melt_wide.md), [`transpose_table()`](https://shepherd70.github.io/tritonIngest/reference/transpose_table.md) | Detection remains heuristic and should be reviewable. |
| Contracts and mapping | [`cf_field()`](https://shepherd70.github.io/tritonIngest/reference/cf_field.md), [`as_contract()`](https://shepherd70.github.io/tritonIngest/reference/as_contract.md), [`contract_fields()`](https://shepherd70.github.io/tritonIngest/reference/contract_fields.md), [`contract_fingerprint()`](https://shepherd70.github.io/tritonIngest/reference/contract_fingerprint.md), [`auto_map()`](https://shepherd70.github.io/tritonIngest/reference/auto_map.md), [`apply_column_map()`](https://shepherd70.github.io/tritonIngest/reference/apply_column_map.md), [`complete_to_contract()`](https://shepherd70.github.io/tritonIngest/reference/complete_to_contract.md), [`validate_against_contract()`](https://shepherd70.github.io/tritonIngest/reference/validate_against_contract.md), [`contract_is_ready()`](https://shepherd70.github.io/tritonIngest/reference/contract_is_ready.md) | Domain contracts stay in consumers. |
| Mapping profiles | [`mapping_profiles_dir()`](https://shepherd70.github.io/tritonIngest/reference/mapping_profiles_dir.md), [`save_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/save_mapping_profile.md), [`load_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/load_mapping_profile.md), [`list_mapping_profiles()`](https://shepherd70.github.io/tritonIngest/reference/list_mapping_profiles.md), [`delete_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/delete_mapping_profile.md), [`upgrade_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/upgrade_mapping_profile.md) | Current schema is v2; stale contract/header fingerprints fail. |
| Censored values | [`parse_censored()`](https://shepherd70.github.io/tritonIngest/reference/parse_censored.md), [`apply_substitution()`](https://shepherd70.github.io/tritonIngest/reference/apply_substitution.md), [`working_values()`](https://shepherd70.github.io/tritonIngest/reference/working_values.md) | Preserve censor direction and keep lower/upper limits distinct. |
| Units | [`convert_units()`](https://shepherd70.github.io/tritonIngest/reference/convert_units.md) | Explicit ladders only; no general unit algebra. |
| Validation kernel | [`check_required_columns()`](https://shepherd70.github.io/tritonIngest/reference/check_required_columns.md), [`check_column_types()`](https://shepherd70.github.io/tritonIngest/reference/check_column_types.md), [`check_no_na()`](https://shepherd70.github.io/tritonIngest/reference/check_no_na.md), [`check_unique()`](https://shepherd70.github.io/tritonIngest/reference/check_unique.md), [`check_range()`](https://shepherd70.github.io/tritonIngest/reference/check_range.md), [`check_monotonic()`](https://shepherd70.github.io/tritonIngest/reference/check_monotonic.md), [`type_matches()`](https://shepherd70.github.io/tritonIngest/reference/type_matches.md), [`validation_abort()`](https://shepherd70.github.io/tritonIngest/reference/validation_abort.md) | Checks return messages so consumers can collect failures. |
| Cache | [`cache_dir()`](https://shepherd70.github.io/tritonIngest/reference/cache_dir.md), [`write_cache()`](https://shepherd70.github.io/tritonIngest/reference/write_cache.md), [`read_cache()`](https://shepherd70.github.io/tritonIngest/reference/read_cache.md), [`cached_ingest()`](https://shepherd70.github.io/tritonIngest/reference/cached_ingest.md) | v2 is backend- and transformation-aware. |
| Artifacts and diagnostics | [`write_canonical_bundle()`](https://shepherd70.github.io/tritonIngest/reference/write_canonical_bundle.md), [`read_canonical_bundle()`](https://shepherd70.github.io/tritonIngest/reference/read_canonical_bundle.md), [`tabular_diagnostic()`](https://shepherd70.github.io/tritonIngest/reference/tabular_diagnostic.md) | Shared interchange schemas are pinned to spec 1.0.0. |

## Repository map

| Path | Responsibility |
|----|----|
| `R/read.R` | Content sniffing, all-text reads, and Excel/date coercion. |
| `R/sheets.R` | Sheet visibility, multi-sheet reads, and OOXML formula/merge inspection. |
| `R/clean.R` | Header recovery and structural cleanup. |
| `R/layout.R` | Layout inference and wide/transposed reshaping. |
| `R/contract.R` | Contract construction, mapping, coercion, validation, and readiness. |
| `R/profiles.R` | Versioned mapping-profile persistence and compatibility checks. |
| `R/censored.R` | Left/right censor parsing and working-value policies. |
| `R/units.R` | Explicit unit normalization and conversion ladders. |
| `R/validate.R` | Generic composable validation checks. |
| `R/cache.R` | Transformation-aware RDS/Parquet materialization cache. |
| `R/artifacts.R` | Verified Parquet/Feather interchange bundles. |
| `R/diagnostics.R` | Structured cross-language diagnostics. |
| `R/utils.R` | Internal hashing, atomic-write, locking, and normalization helpers. |
| `tests/testthat/` | Unit, integration, optional dependency, spec, and secure-workbook tests. |
| `tests/REAL-WORKBOOK-VALIDATION.md` | Private workbook validation procedure. |
| `audits/` | Historical findings and engineering rationale; verify status against current code. |
| `man/` and `NAMESPACE` | Generated by roxygen2; do not edit directly. |
| `NEWS.md` | Authoritative release-level behavior and breaking changes. |
| `DESIGN.md` | Original architecture/migration plan; currently needs reconciliation. |
| `renv.lock` | Runtime dependency lock; not a complete development environment. |
| `.github/workflows/R-CMD-check.yaml` | Five-job R package check matrix plus shared-spec checkout. |
| `.github/workflows/pkgdown.yaml` | Site build on PRs and deployment to `gh-pages` otherwise. |

## Versioned records and compatibility

| Record | Current schema | Compatibility behavior |
|----|----|----|
| Materialization cache | `triton-cache/v2` | Legacy v1 entries are cache misses and are reparsed. |
| Mapping profile | `triton-mapping-profile/v2` | V1 requires explicit [`upgrade_mapping_profile()`](https://shepherd70.github.io/tritonIngest/reference/upgrade_mapping_profile.md); do not silently bless it. |
| Canonical artifact manifest | `tabular-artifact/v1` | Readers reject unsupported schemas and verify artifact identity. |
| Structured diagnostic | `tabular-diagnostic/v1` | Diagnostic codes conform to `tabular-ingestion-spec` 1.0.0. |

These identifiers are interoperability contracts. Changing a record
shape requires a new schema version, migration/compatibility tests, and
coordinated consumer changes. Do not mutate an existing Git tag to
distribute a schema change.

One internal compatibility detail is easy to miss: `%||%` intentionally
treats `NULL`, length-zero values, and a first-element `NA` as missing.
On R 4.4 and newer it intentionally masks the base operator, whose
behavior differs. Audit uses of this helper carefully rather than
replacing it mechanically.

## Downstream consumers

The versions below were verified from each repository’s `DESCRIPTION`
and `renv.lock`. The declared minimum is an API floor; the GitHub tag in
the lock is the reproducible installed version.

| Consumer | Declared minimum | Locked GitHub tag | Handoff note |
|----|---:|---:|----|
| `bw-analysis-code` | `>= 0.7.1` | `v0.7.1` | Current with this release. Catch, effort, and FHAP contracts delegate to the shared engine. |
| `water-chemistry-qaqc` | `>= 0.7.0` | `v0.7.0` | Migration is complete even though `DESIGN.md` still says Phase 3 is not started. |
| `electrocpue` | `>= 0.4.0` | `v0.4.2` | Several fail-closed and schema changes landed after its pin. |
| `tritonmr` | `>= 0.4.0` | `v0.4.2` | Uses the generic validation kernel and should be regression-tested before upgrading. |

Versions `0.6.0` and `0.7.0` include intentional breaking/safety
changes. Before raising a consumer pin:

1.  Read every intervening `NEWS.md` entry.
2.  Update both the `DESCRIPTION` minimum/`Remotes` entry and
    `renv.lock`.
3.  Restore the consumer in a clean library.
4.  Run its full unit and package checks, including Shiny or workflow
    smoke paths.
5.  Test representative source workbooks for mapping, censor, header,
    and cache behavior.
6.  Merge consumer upgrades independently so failures identify the
    affected boundary.

## Safety invariants

Preserve these defaults unless a caller makes an explicit, reviewable
override:

- Read fragile source values as text before applying typed contracts.
- Verify file content signatures; do not trust filename extensions.
- Treat duplicate source headers as errors by default.
- Keep formula provenance and missing cached formula results visible.
- Keep fuzzy mapping disabled by default (`max_distance = 0`).
- Treat coercion loss as an error by default.
- Parse censor notation before numeric coercion.
- Keep right-censor bounds separate from detection limits.
- Validate contracts in strict mode and require real populated rows for
  readiness.
- Bind reusable profiles to both contract and ordered-header
  fingerprints.
- Bind cache hits to the source, backend, artifact, transformation, and
  package identity.
- Keep source checksums, contract fingerprints, diagnostics, and
  transform identity with canonical interchange artifacts.
- Keep domain rules and private data out of this repository.

Fail-closed does not mean every override is forbidden. It means `warn`,
`repair`, fuzzy matching, skipped verification, or lossy coercion must
be an intentional policy choice with diagnostics and review evidence.

## Recommended next work

### Priority 0: reconcile the source of truth

1.  Update `README.md` and `DESIGN.md` for the released `v0.7.1` state.
    Specifically:

    - change “v0.7.1 development” to released/current wording;
    - make `auto_map(max_distance = 0)` the normative safe API;
    - add sheet inspection, transposed layouts, diagnostics, cache v2,
      artifacts, date/time types, and the newer source modules;
    - mark the `water-chemistry-qaqc` migration complete;
    - retain Phase 4 as the remaining BW chemistry/metals integration;
      and
    - replace historical “current v0.5.0” dependency examples.

2.  Turn the actual remaining work into GitHub issues. There were no
    open issues at handoff, so `DESIGN.md` and the audit documents
    currently act as an informal and partly stale backlog. Link each new
    issue to a current reproducer or acceptance test.

3.  Add a release checklist that keeps `DESCRIPTION`, `NEWS.md`, README
    status, design status, the `renv` snapshot, pkgdown, and downstream
    pins consistent.

### Priority 1: converge downstream consumers

1.  Plan and test upgrades of `water-chemistry-qaqc` from v0.7.0 and
    `electrocpue`/`tritonmr` from v0.4.2. Do not assume a version bump
    is mechanical because later releases deliberately changed failure
    behavior.
2.  Complete the original Phase 4 payoff in `bw-analysis-code`: define a
    consumer-owned chemistry/metals contract and route tissue-metals and
    sediment ingestion through the shared censor/unit primitives.
3.  Add a cross-consumer compatibility gate or scheduled workflow that
    checks proposed `tritonIngest` releases against each supported
    consumer pin.

### Priority 1: make verification reproducible

1.  Define a reproducible development/check dependency policy.
    `testthat`, `zip`, and `arrow` are Suggested packages and are absent
    from the explicit runtime snapshot. Consider `Config/Needs/check`, a
    separate check profile, or documented lockfile inclusion.

2.  Add minimized, de-identified golden fixtures for the failure classes
    found in the June/July audits. The secure real-workbook harness is
    valuable, but it cannot replace a committed full-pipeline corpus
    available to every contributor and CI job.

3.  Add explicit full-flow cases covering:

    `read -> inspect -> clean -> detect/transpose/melt -> map -> parse -> validate -> cache/bundle`

    Exercise RDS and Arrow backends, formula gaps, duplicate headers,
    stale profiles, left/right censoring, and transformation-driven
    cache misses.

4.  Make CI output explicit about skipped optional tests. A green check
    should make it obvious whether `arrow`, `zip`, the shared spec, and
    private real-workbook paths ran or skipped.

### Priority 2: operational hardening

- Establish a measured performance corpus before optimizing. Correctness
  and provenance are more important than speculative vectorization or
  parallelism.
- Exercise bounded cache locking under concurrent writers on Windows and
  Linux if cache sharing becomes a production workflow.
- Define retention and privacy rules for manifests, diagnostics, and
  cache directories. Manifests contain source names and fingerprints
  even when they contain no cell values.
- Keep the R implementation authoritative. If Python services are added
  at an operational boundary, exchange versioned Arrow artifacts and run
  one shared conformance suite rather than allowing semantic
  implementations to drift.

## Development conventions

- Preserve raw source representation until interpretation is explicit
  and tested.

- Keep generic ingestion behavior here and domain contracts/rules in
  consumers.

- Prefer fail-closed defaults with structured diagnostics for overrides.

- Add a regression test for every correctness or data-provenance defect.

- Keep functions narrow by module; do not collapse reader, contract,
  cache, and artifact responsibilities into one workflow function.

- Document exported functions with roxygen2, then regenerate `NAMESPACE`
  and `man/*.Rd`:

  ``` r

  roxygen2::roxygenise()
  ```

- Review generated diffs rather than editing generated files by hand.

- Update `NEWS.md` for behavior changes and `DESCRIPTION` for version or
  dependency changes.

- Update `renv.lock` deliberately and verify that line-ending
  normalization does not obscure the semantic diff.

- Keep schemas versioned and old-format behavior explicit.

- Never force-push or retarget a released tag.

- Never commit client workbooks, raw outputs, credentials, local mount
  paths, or cell values derived from private sources.

## CI, release, and pkgdown

`.github/workflows/R-CMD-check.yaml` runs on pushes to `main`/`master`,
pull requests, and manual dispatch. Its five jobs cover:

- macOS with R release;
- Windows with R release;
- Ubuntu with R devel;
- Ubuntu with R release; and
- Ubuntu with R oldrel-1.

Every job checks out `tabular-ingestion-spec` at immutable tag `v1.0.0`
into `.spec` before installing dependencies and running `R CMD check`.

`.github/workflows/pkgdown.yaml` builds the site for pull requests. On
other trigger types it deploys `docs/` to `gh-pages`. The local `docs/`
directory is ignored and should not be committed to `main`.

A safe release sequence is:

1.  Reconcile code, roxygen output, tests, `DESCRIPTION`, `NEWS.md`,
    README, and design status.
2.  Restore a clean project library and run the full local suite with
    optional dependencies present.
3.  Run the shared-spec and approved secure-workbook gates.
4.  Open a PR and require the five package checks plus pkgdown.
5.  Test downstream consumers against the candidate commit/tag.
6.  Merge, create a new immutable semantic-version tag, and publish the
    GitHub release.
7.  Confirm the tag’s CI and the pkgdown/Pages deployment.
8.  Raise consumer pins in their own reviewed changes.

## Troubleshooting

- **A test appears to use old behavior:** inspect
  [`.libPaths()`](https://rdrr.io/r/base/libPaths.html) and
  `packageVersion("tritonIngest")`. Load the source with
  [`pkgload::load_all()`](https://pkgload.r-lib.org/reference/load_all.html)
  after restoring `renv`.
- **Arrow tests skip or bundle functions fail:** install `arrow` in the
  active project library. Do not interpret skipped bundle tests as
  verification.
- **Workbook visibility/formula tests skip:** install `zip` and confirm
  the fixture can be opened as OOXML.
- **The shared-spec test skips:** set `TABULAR_INGESTION_SPEC_DIR` to a
  checkout whose `VERSION` is exactly `1.0.0`.
- **Real-workbook tests skip:** set `TRITON_REAL_WORKBOOK`. Set
  `TRITON_REAL_WORKBOOK_PYTHON` to a Python interpreter with `openpyxl`
  for the independent-reader digest.
- **A workbook reads the wrong sheet:** inspect
  [`list_sheets()`](https://shepherd70.github.io/tritonIngest/reference/list_sheets.md).
  Sheet 1 may be hidden or `veryHidden`; name the intended sheet
  explicitly.
- **Formula cells are blank/stale:** `readxl` reads cached values and
  does not recalculate Excel. Inspect workbook diagnostics and reject
  with `formula_policy = "error"` when cached results cannot be trusted.
- **A duplicate-header failure appears:** stop and resolve semantic
  identity using source position/provenance. Name repair alone cannot
  tell two analytes apart.
- **Mapping changed unexpectedly:** confirm fuzzy matching is disabled,
  inspect exact-name-versus-synonym warnings, and compare ordered source
  headers.
- **Coercion rejects data:** inspect the raw tokens. Parse censoring and
  qualifiers before applying numeric types; use `loss = "warn"` or
  `"allow"` only with recorded review.
- **A cache unexpectedly misses:** compare source fingerprint, backend,
  artifact checksum, and transformation context. A safe miss and reparse
  is preferable to a stale hit.
- **A mapping profile is rejected:** compare its contract and
  ordered-header fingerprints. Upgrade a v1 record explicitly and
  reapprove mappings.
- **Unicode censor/unit behavior differs by platform:** keep source
  files ASCII-safe where implemented and use runtime code-point
  normalization; reproduce under Windows/non-UTF-8 locales before
  changing aliases.

## Handoff completion checklist

Before handing the repository on again:

Working tree is clean and the branch is synchronized with its upstream.

[`renv::status()`](https://rstudio.github.io/renv/reference/status.html)
has no unintended drift.

The intended source version, not a stale globally installed package, was
tested.

All unit tests and `R CMD check` pass on the supported matrix.

Optional `arrow`, `zip`, shared-spec, and approved private-workbook
gates ran when relevant.

Roxygen output is regenerated when the public API changed.

`DESCRIPTION`, `NEWS.md`, README, design status, and pkgdown agree.

Versioned schemas and backward-compatibility behavior are documented and
tested.

Affected downstream consumers pass against the candidate version.

No private data, cell values, credentials, cache files, or local paths
are tracked.

This handoff and the GitHub issue backlog reflect current limitations,
not superseded audit findings.
