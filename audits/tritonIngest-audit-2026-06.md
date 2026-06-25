# tritonIngest — Audit (2026-06)

Dimensions run: the three core dimensions (Correctness; Security & provenance via
`pi_audit.py` + commit history; Maintainability & dependencies), plus two
conditionals that fit the repo: **R package conventions** (DESCRIPTION /
NAMESPACE / roxygen / tests / Imports coherence) and **data-transformation
correctness** — the numerical-validity angle that stands in for "statistical
validity" here, since this package is pure ingestion plumbing: unit-conversion
direction & coverage, non-detect/censored parsing, and Excel-date coercion.
Skipped as not applicable: regulatory defensibility and citation/methods
integrity (the package deliberately contains no reported figures, coefficients,
or bibliography — it is "plumbing only" per DESIGN.md §2) and financial-data
correctness.

**Overall health: good.** This is a young (v0.3.1), well-structured,
well-tested infrastructure package with clean pure-function design, per-function
roxygen, and a sensible test suite across all nine modules. The injection scan
is clean after triage (zero genuine hits) and git integrity checks pass. Nothing
is critical. The items worth acting on are a handful of *silent-failure* paths in
the data-transformation core (unit conversion that only covers mass/volume; length
mismatches in the censored helpers; permissive Excel-date coercion) and one
concrete packaging defect (three base packages used via `::` but not declared in
`Imports`, which the freshly-added R-CMD-check CI will flag). The rest are minor
hygiene: a no-op `.gitignore` line, README/DESIGN drift against the current
version, and slug-collision edges.

## Critical

- None. `pi_audit.py` reported 2 CRITICAL `shell:secret-to-network` hits, both in
  `renv/activate.R:642` / `:648` — these are stock vendored renv bootstrap code
  (`renv_bootstrap_github_token()` driving a `curl`/`wget` download of renv with
  an `Authorization: token` header). Confirmed standard renv boilerplate, not
  injected. Triaged as false positives. A second pass (2026-06-14) re-ran the
  scanner and got the same 9 findings — these 2 renv CRITICALs plus 7 MEDIUM
  `agent:secretly-silently` hits, every one the benign English word "silently"
  in two roxygen comments (`R/cache.R:9`, `R/units.R:11`) and in the body of this
  report quoting its own findings. Zero genuine hits; no secrets, invisible-
  Unicode, or HTML-comment payloads. `git fsck` returns clean and the working
  tree is clean.

## Major

- `R/units.R:18-33` — `convert_units()` only knows the **mass/volume** ladder
  (`g/L, mg/L, ug/L, ng/L`). Any **mass/mass** unit (`mg/kg`, `µg/g`, `ng/g`),
  which is exactly what the tissue-metals and sediment workbooks targeted by
  DESIGN.md §5 Phase 4 use, falls through to `NA` with no distinct signal — the
  same `NA` you'd get from a genuinely missing value. A caller that doesn't
  special-case `NA` will silently blank or drop solid-matrix data.
  Fix: add the mass/mass ladder, and/or distinguish "unit class unsupported"
  from a value-level `NA` (e.g. `warning()` or a separate return), or explicitly
  document mass/mass as out of scope so Phase 4 doesn't assume coverage.

- `DESCRIPTION:20-27` — base packages **`stats`, `tools`, `utils` are used via
  `::` but not declared in `Imports`**: `stats::setNames` (`R/contract.R:97,166`,
  `R/profiles.R:121`), `tools::file_ext` (`R/read.R:25`),
  `tools::file_path_sans_ext` / `tools::md5sum` (`R/profiles.R`, `R/cache.R`),
  `utils::adist` (`R/contract.R:111`). `R CMD check` — now wired up via the new
  `.github/workflows/R-CMD-check.yaml` — emits a NOTE for `::` calls to
  undeclared packages. Fix: add `stats`, `tools`, `utils` to `Imports:`.

- `R/censored.R:29-37` and `R/censored.R:89-97` — the censored helpers do **no
  length validation** across their parallel vectors, so a length mismatch
  misaligns silently instead of erroring. `parse_censored()` does
  `rep(detection_limit, length.out = n)`, so a DL column of the wrong length is
  recycled and attaches the wrong detection limit to the wrong row with no
  warning. `apply_substitution()` indexes `detection_limit[idx]` with no check
  that `value`, `censored`, and `detection_limit` are the same length —
  over-indexing yields `NA` rather than an error. For lab data this is a
  data-integrity trap. Fix: assert equal lengths (allowing an explicit length-1
  `detection_limit` recycle) and `stop()` on any other mismatch.

## Minor

- `R/read.R:54-63` — `coerce_excel_date()` has three permissive/silent paths:
  (1) anything `as.numeric()` can parse is treated as an Excel serial, so a
  4-digit year (`"2024"`) or numeric code becomes a 1900s-era date rather than
  being rejected; (2) string dates are parsed only with `format = "%Y-%m-%d"`, so
  `"2024/08/22"`, `"22-08-2024"`, etc. become `NA` silently with no parse-note
  (unlike `parse_censored()`, which records diagnostics); (3) the 1900 date
  system is hardcoded, so a Mac/1904-system workbook would be off by ~4 years.
  Fix: bound the serial range or require the caller to declare serial-vs-string,
  accept the common date formats (or return a note vector), and document the
  1900-system assumption.

- `R/contract.R:128-136` — `.cf_coerce()` integer path
  `as.integer(round(as.numeric(x)))` silently returns `NA` on values above
  `.Machine$integer.max` (the overflow warning is suppressed) and applies
  round-half-to-even (`round(80.5) == 80`). Fine for years/counts but a silent
  surprise for large numeric IDs. Fix: note the behaviour, or validate the range.

- `R/units.R:21` — only the U+00B5 micro sign (`"µg/l"`) is in the factor table;
  the visually identical Greek-mu variant U+03BC (`"μg/L"`, common from
  instrument exports) won't match and returns `NA`. Fix: normalise both micro
  code points to one in `norm()`.

- `.gitignore:9` — `/man/        # regenerate with devtools::document()` keeps the
  inline `#` comment on the *pattern* line. Git does not treat a trailing `#` as a
  comment, so the whole line becomes a literal pattern that matches nothing — the
  rule is a silent no-op (verified: `man/*.Rd` are tracked, `git check-ignore`
  reports them not ignored). The current effect is actually correct — `man/`
  *should* be tracked so `remotes::install_github()` and CI ship help files — but
  the intent is ambiguous and a future "fix" of the comment would flip behaviour
  and break installed docs. Fix: delete the `/man/` line (you want man/ tracked),
  or put the comment on its own line if you genuinely intend to ignore it.

- `.gitignore:10` — `/docs/` ignores the entire `docs/` tree (meant for pkgdown
  output) and therefore also swallows hand-authored docs placed there; this audit
  report had to be force-added. Fix: narrow the ignore to the pkgdown build output
  rather than the whole directory if you intend to keep written docs under `docs/`.

- `README.md:57-59` / `DESIGN.md:122-142` — documentation drift. README says
  "Status: v0.1.0 — Phase 0–1" but `DESCRIPTION` is `0.3.1`; the README "What it
  does" list omits the materialisation cache (`R/cache.R`) and the generic
  validation kernel (`R/validate.R`); DESIGN.md §4's package structure omits
  `cache.R`, `validate.R`, and `utils.R`. There is no `NEWS.md` recording the
  0.1 → 0.3 changes. Fix: refresh the README status + feature list and add a
  `NEWS.md`.

- `R/profiles.R:32-38` and `R/cache.R:73-79` — slug collision. Two distinct
  profile names (or cache keys) that normalise to the same slug overwrite each
  other's file silently (`"2025 master"` and `"2025_master"` both → `2025-master`).
  `cache.R` already guards source-*derived* keys with a path hash
  (`.key_from_source`), but an explicit `key=`/profile name does not. Fix: detect
  an existing-but-different-name collision, or append a short hash.

- `R/layout.R:25-26` vs `R/censored.R:17` — **the non-detect token lists diverge.**
  `is_value_like()` (used by `detect_layout()`) recognises only
  `ND, N.D., BDL, DNQ, U`, while `parse_censored()`'s `ND_TOKENS` recognises eight
  (adds `B.D.L.`, `NON-DETECT`, `NONDETECT`). A wide column whose non-detects use
  the longer notation therefore may not clear the `is_value_like()` threshold, so
  `detect_layout()` can undercount value columns and misclassify a wide table —
  even though `parse_censored()` would happily read those same cells as censored.
  The two functions also each carry their own copy of the `^<\s*[0-9.eE+-]+$`
  "<DL" regex. Fix: hoist one shared token vector + regex and reference it from
  both, so a future token addition can't fall out of sync.

- `R/layout.R:102-103` — `melt_wide()` unconditionally does `long$units <- ...`
  and then selects `c(id_cols, "parameter", "value_raw", "units")`. If the source
  already has an id column literally named `units` (plausible: wide lab/field
  files often carry a units column), its real values are overwritten with `NA`
  (whenever the `units=` argument is not passed) and `units` then appears twice in
  the final selection, producing a duplicated/garbled output column. A pre-existing
  `parameter` or `value_raw` id column collides the same way. Fix: detect the name
  clash and error (or suffix the reserved output names) instead of silently
  clobbering.

- `R/utils.R:5-7` — the local `%||%` is **NA-coalescing** (returns `b` when `a`
  is `NULL`, length-0, *or* `is.na(a)[1]`), which diverges from base R's `%||%`
  (R ≥ 4.4) and rlang's (both NULL-only). It is genuinely needed for the declared
  `R (>= 4.2)` floor (base lacks `%||%` before 4.4), but on R ≥ 4.4 it shadows
  base with surprising semantics. Fix: keep it but document the divergence, or
  rename (e.g. `%|NA|%`) so a reader isn't misled by the familiar operator.

- Provenance (informational) — commit history attributes one person to three
  emails: `shepherd70@gmail.com`, `travis.shepherd@tritonenv.com`, and the GitHub
  noreply `134653832+shepherd70@users.noreply.github.com` (DESCRIPTION uses the
  tritonenv address). Not a security issue. AI co-author trailers (`Claude Fable
  5`, `Claude Opus 4.8`) are present and expected. Fix: set a consistent
  `git config user.email` if uniform attribution is wanted.

- `DESCRIPTION` — no `URL` / `BugReports` fields though DESIGN.md names a GitHub
  repo, and no `cph` role on the author. Packaging polish; add when the repo is
  published.

## Could not verify

- I did not execute the test suite or `R CMD check` in this pass — the renv
  library is not restored locally and a restore would download packages. The
  undeclared-imports NOTE and any other check output above are predicted from
  reading the code, not confirmed by a run. Recommend one `devtools::check()` /
  CI matrix run to confirm.
- Excel 1904-date-system exposure depends on the provenance of the actual source
  workbooks, which are (correctly) not in this repo.
- The 2 CRITICAL `pi_audit` hits are in vendored `renv/activate.R`; I read the
  flagged region and confirmed it is stock renv bootstrap, but did not byte-diff
  it against a pristine renv of the same version.
