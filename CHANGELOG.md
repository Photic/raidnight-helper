# Changelog

## [Unreleased]

### Changed

- Auto, Balance, locks and filling open slots now work on the groups that play, which follow the size of the raid: groups 1–4 for up to 20 players, and groups 1–6 (halves 1–3 and 4–6) for more. Inside a Mythic raid it stays groups 1–4, and in Mythic flex it is groups 1–5 (halves 1–3 and 4–5).
- Auto keeps the two halves as even in size as the groups allow, for example 9 and 9 with 18 players instead of 10 and 8.
- When the halves differ in size, Balance aims for each half's share of the players (60% and 40% with 15 and 10 players) and says so in chat.

## [1.0.2] - 2026-10-21

First release.

### Added

- Group sorting from a layout pasted from the Raidnight website (text or an `RS1:` code).
- Group grid with class colours and role icons; dragging a name moves the player in the raid too.
- Preview of who is in the wrong group, and inviting players on the list who are missing.
- Option to fill open slots with players who are not on the list, by role and class.
- Locks: keep a player out of groups 1–4 when sorting, and in place when balancing.
- Undo: brings back the layout from before Auto, Balance or filling open slots.
- Auto: picks groups 1–4 from the whole raid and balances them by role and class.
- Balance: evens out the damage of groups 1+2 and 3+4 by the last boss pull.
- Boss layouts: save a layout for each boss of the current tier and load it with one click, or save the raid's groups automatically on every pull.
- Interface in English, German, French, Spanish, Italian, Portuguese, Russian, Korean and Chinese (Simplified and Traditional).
- `/raidnight` (or `/rn`) opens the window; `apply`, `auto`, `balance`, `invite` and `stop` work as commands.
