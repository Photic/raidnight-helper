**Raidnight Helper** is the in-game companion addon for the Raidnight website. It is built to grow: each tool for raid night lives in the same addon.

The in-game interface follows the language of the game client: English, German, French, Spanish, Italian, Portuguese, Russian, Korean and Chinese (Simplified and Traditional). Text without a translation shows in English.

---

## Features

### RaidSort
Paste a group layout from the website and the raid sorts itself into the planned groups.

- Open the window with `/raidsort` (or `/rsort`) and paste the layout with Ctrl+V.
- Accepts plain text or the website's `RS1:` code.
- A live preview shows how many players are in the wrong group, who on the list is not in the raid, and which names match more than one player.
- **Sort raid** moves players one at a time and waits for each move to land before the next. Sorting pauses in combat and continues when combat ends.
- Optionally moves players who are not on the list into the free groups.
- **Invite missing** invites everyone on the list who is not in the raid yet.
- Names match regardless of case and accents, so `Majestic` finds `Májestíc`. Write `Name-Realm` when two players share a name.
- Requires raid leader or assistant to move players.

#### Boss layouts

A row of boss icons at the top of the window shows the bosses of the current raid tier, read from the Encounter Journal. Pick the raid in the dropdown; it starts on the raid you are in.

- Click a boss to load its saved layout into the text box.
- **Save** stores the text box under the selected boss. **Delete** removes it.
- Faded icons have nothing saved yet. Hover an icon to see when its layout was saved.
- With **Save the raid's groups to the boss on pull** checked (the default), every pull stores the raid's groups as they are under that boss, so the next click on it brings back the groups from the last pull. Raid Finder pulls are skipped.
- Layouts are stored account-wide in WoW's saved variables, so addon updates keep them.

#### Text format

```
Group 1: Adelie, Goatjugs, Hoolyhayat, Kitchlol, Meilian
Group 2: Gothmog, Hadier, Májestíc, Pepì, Sectorclear
```

Names can also go one per line under a `Group N` line, and `Gruppe`, `G1` and `1.` work as group headers too.

#### Commands

| Command | Action |
|---|---|
| `/raidsort` | Open or close the window |
| `/raidsort apply` | Sort by the last pasted layout (handy in a macro) |
| `/raidsort invite` | Invite players on the list who are not in the raid |
| `/raidsort stop` | Stop a sort in progress |
