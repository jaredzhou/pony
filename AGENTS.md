# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

## Project Structure

- MoonBit packages are organized per directory, for each directory, there is a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (common, ending in `_test.mbt`) and whitebox test files
  (ending in `_wbtest.mbt`).

- In the toplevel directory, this is a `moon.mod` file listing about the
  module and some meta information.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

After making changes, run these steps in order. CI enforces the same
checks on every push to main and on every PR (`.github/workflows/ci.yml`):

- `moon check --deny-warn` — type-check with warnings treated as errors.
- `moon fmt` — format the code. CI runs `moon fmt --check`, so make sure
  it produces no diff.
- `moon info` — regenerate `.mbti` interface files. CI checks
  `git diff --exit-code` immediately afterwards, so commit any `.mbti`
  changes. If `.mbti` is unchanged, the change is a safe refactoring
  that does not affect the public API.
- `moon test` — run the full test suite. Use `moon test --update` when
  snapshots have changed.

When writing tests, prefer `inspect` + `moon test --update` for
snapshots; use `assert_eq` only when inside loops where each snapshot
value varies. Run `moon coverage analyze > uncovered.log` to see which
parts of your code are not covered by tests.
