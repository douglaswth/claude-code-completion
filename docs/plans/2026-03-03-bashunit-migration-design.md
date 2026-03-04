# bashunit Migration Design

## Goal

Replace the hand-rolled test framework with bashunit to eliminate boilerplate, gain rich assertions, get built-in coverage tracking, and produce better test output.

## Current State

8 test files in `tests/` using a manual framework:
- Each file repeats `fail()`/`pass()`/`FAILURES` boilerplate (~15 lines)
- `_simulate_completion` helper duplicated in 4 files
- Mock `claude` commands defined per-file with overlapping setup
- ~45 assertions total across all files
- No coverage tooling

## Approach: Full Migration

Rewrite all test files to bashunit conventions in a single pass. The suite is small enough that incremental migration would add complexity without meaningful risk reduction.

## Shared Test Helper (`tests/test_helper.bash`)

Provides infrastructure shared across all test files:

- **`create_mock_claude(mock_bin_dir)`** — writes a base mock `claude` script with `--version` and `--help` handlers. Tests append/override case branches for their specific needs.
- **`simulate_completion(cmdline)`** — sets up `COMP_LINE`, `COMP_WORDS`, `COMP_CWORD`, calls `_claude`, returns `COMPREPLY`.
- **`set_up` / `tear_down`** — create and clean temp dirs for `XDG_CACHE_HOME` and `MOCK_BIN`.

## Test File Mapping

| Current | New | Assertion approach |
|---|---|---|
| `test_skeleton.bash` | `skeleton_test.bash` | `assert_successful_code`, `assert_true` |
| `test_cache.bash` | `cache_test.bash` | `assert_string_starts_with`, `assert_not_empty`, `assert_directory_exists`/`not_exists` |
| `test_help_parsing.bash` | `help_parsing_test.bash` | `assert_file_exists`, `assert_file_contains` |
| `test_completion.bash` | `completion_test.bash` | `assert_contains` on `simulate_completion` output |
| `test_flag_args.bash` | `flag_args_test.bash` | `assert_contains` for model/format/permission completions |
| `test_resume.bash` | `resume_test.bash` | `assert_equals` for session count, `assert_contains` for UUIDs |
| `test_fallbacks.bash` | `fallbacks_test.bash` | `assert_same` for message extraction, `assert_contains` for plugin names |
| `test_subcommand_args.bash` | `subcommand_args_test.bash` | `assert_contains` for MCP/plugin name completions |

## Coverage

bashunit has built-in coverage using bash's `DEBUG` trap:
- Run with `bashunit tests/ --coverage --coverage-paths claude.bash`
- HTML reports via `--coverage-report-html coverage/`
- Add `coverage/` to `.gitignore`
- Defer minimum threshold until we see the baseline

## Running Tests

```bash
# All tests
bashunit tests/

# With coverage
bashunit tests/ --coverage --coverage-paths claude.bash
```

## GitHub Actions CI

Add `.github/workflows/test.yml` to run tests on every push and PR:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bashunit
        run: |
          curl -s https://bashunit.typeddevs.com/install.sh | bash
      - name: Run tests
        run: ./lib/bashunit tests/
      - name: Run tests with coverage
        run: ./lib/bashunit tests/ --coverage --coverage-paths claude.bash
```

In CI, bashunit is installed via the official install script into `lib/bashunit`. Add `lib/` to `.gitignore`.

## Local Installation

bashunit is assumed pre-installed locally (e.g. `brew install bashunit`). Document as a prerequisite in README/CLAUDE.md.
