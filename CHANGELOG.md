# Changelog

## [Unreleased]

### Added

- Lists with a name of their own, such as `Left: ...` and `Right: ...`, can be pasted. Each list fills groups of five in order, so with 14 names on each side, Left takes groups 1–3 and Right groups 4–6.
- **Swap halves** (or `/raidnight swap`) trades the two halves of the groups that play in the layout: groups 1–3 with 4–6, or 1+2 with 3+4. While the raid is still forming, it uses the halves the raid will have once everyone on the list is in, so the sides stay together. The raid stays as it is until **Sort raid**.
- A name on the list that is not in the raid can be taken off it: right-click it and pick **Remove from list**, or drag it out of the window.
- Names that are not in the raid can wait in **Not on list**: drop them there and they stay, in grey, until you drag them back into a group. The layout keeps them on a `Not on list:` line, so boss layouts and **Send** keep them too.
- Boss notes from the website (`EncounterID:...;Difficulty:...`) can be pasted. The groups come from the note's first block of lists, and the note selects its boss and difficulty and is saved there at once. **Undo** takes it back.
- The note window (`/raidnight note`) shows the whole boss note. Edit it and press **Apply** (or `/raidnight note apply`) to make its groups the layout. When the groups change, the note follows: its Left/Right lists, and timeline lines that tag exactly those players, get the players now in the groups each list filled. A boss's note is saved with its layout.
- Boss layouts per difficulty: each boss has a layout for Normal, Heroic and Mythic. Pick the difficulty with the buttons next to the raid dropdown, or with `/raidnight normal`, `heroic` or `mythic`. Opening the window inside a raid, or a pull, picks the raid's difficulty.

### Changed

- The group grid shows the role icons of the game's raid frames: tank, healer and damage. Melee and ranged share the damage icon, as they do there.
- Layouts saved before there were difficulties become the Mythic ones.
- Auto-save on pull stores the groups under the raid's difficulty.
- **Send** sends the layouts of the difficulty you picked and replaces only that difficulty on the receivers' side. Everyone in the raid needs this version: older versions are asked to update, and their pushes are not taken in.

### Fixed

- Dropping a name that is not in the raid on **Not on list** no longer takes it off the list without a trace, and moving such names no longer tries to move anyone in the raid.

## [1.1.0] - 2026-10-22

### Added

- **Send** in the boss row (or `/raidnight send`) sends the boss layouts of the raid in the dropdown to everyone in the raid with Raidnight Helper, in place of their own layouts for that raid. Only the raid leader and assistants can send, out of combat.

### Changed

- The groups that play now follow the size of the raid. Up to 20 players, groups 1–4 play as before, in halves 1+2 and 3+4. With 21 or more, groups 1–6 play, in halves 1–3 and 4–6. Inside a Mythic raid it stays groups 1–4, and in Mythic flex (up to 25 players) groups 1–5 play, in halves 1–3 and 4–5. Auto, Balance, locks and filling open slots all follow this.
- Auto keeps the halves as even in size as the groups allow: 9 and 9 with 18 players, not 10 and 8.
- When the halves differ in size, Balance aims for each half's share of the players, for example 60% and 40% with 15 and 10 players, and the chat shows that goal.
- Balance's chat lines and the lock tooltip name the groups that play, such as "groups 1+2+3" or "groups 1-6".

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
