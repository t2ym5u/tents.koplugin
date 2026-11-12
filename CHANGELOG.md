# Changelog

All notable changes to this project will be documented in this file.

## [1.6.1] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.6.0] - 2026-11-05

### Changed
- Real puzzles at every size: about one tree for every 5 to 7 squares
  (6×6: 5 to 8 trees, 12×12: 22 to 30). Before, a whole grid held only
  3 to 9 trees, most rows were empty and every puzzle solved itself.
- Difficulty levels now really differ. Every puzzle is checked by a solver
  that reasons like a player, never by trial and error: Easy needs only the
  basic steps (full rows, a tree with one free square, squares around a
  tent), Medium needs 1 to 4 harder steps (a square touching every possible
  tent of a tree, working out how a row's tents can fit), Hard needs more of
  them and has more trees. Easy and Medium were the same puzzles at 6×6.
- A finished grid wins whenever it keeps the rules, even if the trees pair
  up with the tents differently from the generated solution.
- A "Generating puzzle…" bar shows if a puzzle takes a moment to build.
- Today's Daily Challenge puzzle changes once with this update.

### Fixed
- Removed the fallback that, after 60 failed tries, could hand out a puzzle
  that had not been checked for a single solution.

## [1.5.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.5.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.5.0] - 2026-11-04

### Changed
- Much faster puzzle generation: the uniqueness check now leaves out a
  square as soon as its row or column already holds as many tents as its
  clue says, instead of checking the counts only once every tree had a
  tent. 12×12 Hard went from up to 120 ms on a desktop (about 3 s on a Kobo)
  to about 1 ms. Puzzles are the same for almost every seed (still exactly
  one solution); the rare candidate the old check gave up on is now
  checked to the end.
- Opening the game no longer builds a puzzle it then throws away (it was
  generated even when a saved game was about to be restored).

## [1.4.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.4.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.3.0] - 2026-10-30

### Changed
- Redesigned play screen: the board is larger, filling the room the controls
  leave, with a full-width action bar under the status line. The grid's thick
  border is now the board's only frame.
- Trees and tents are drawn as shapes on white cells (a crowned tree, a tent
  with a door) instead of "T" and "^" letters on grey, and grass as a small
  disc instead of a ".".
- The status line shows size, difficulty and "Tents: 3/10", and wraps in
  landscape instead of being cut off. The "Tap=cycle Long=grass" help it used
  to carry is now in the rules.
- The title-bar menu shows "Size: …" and "Difficulty: …" (was the bare
  values), like every other game.
- Once the puzzle is solved (or revealed), the action bar shows "New game" in
  place of Undo/Check/Hint/Reveal, so the next round no longer needs the
  menu.

### Fixed
- Clue numbers overflowed their space: the font fit accepted every size. They
  are now fitted to the cell.
- Using a hint wiped the saved game; it is now kept. When a hint places the
  last tent, the status shows the win message.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps: the first says which cell is about to give, the
  second acts on it. A cell that contradicts the solution is always reported
  before a fresh one is revealed.

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
