# Changelog

All notable changes to this project will be documented in this file.

## [1.1.12] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification — the tree positions
  and row/column tent-count clues shipped as soon as one valid tent
  placement was found, with no check that they pinned down that
  placement uniquely. Measured pre-fix ambiguity of roughly 60-87% unique
  across sizes/difficulties (worse at hard). Added a backtracking
  uniqueness solver and reworked generation to retry the tree/tent
  pairing until one is proven unique. Puzzles are now 20/20 unique at
  every size/difficulty in regression testing, with generation staying
  near-instant.
