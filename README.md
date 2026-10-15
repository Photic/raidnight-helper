**Raidnight Helper** is the in-game companion addon for the Raidnight website. It is built to grow: each tool for raid night lives in the same addon.

The in-game interface follows the language of the game client: English, German, French, Spanish, Italian, Portuguese, Russian, Korean and Chinese (Simplified and Traditional). Text without a translation shows in English.

---

## Features

### Group sorting
Paste a group layout from the website and the raid sorts itself into the planned groups.

- Open the window with `/raidnight` (or `/rn`) and paste the layout with Ctrl+V.
- Accepts plain text or the website's `RS1:` code.
- A live preview shows how many players are in the wrong group, who on the list is not in the raid, and which names match more than one player.
- **Sort raid** moves players one at a time and waits for each move to land before the next. Sorting pauses in combat and continues when combat ends.
- **Fill open slots with players not on the list** (on by default): players on the list keep their groups, and players who are not on it take the open slots in groups 1–4 by role, with the same rules as Auto. Slots of list players who are not in the raid stay free for them; anyone left over goes to the free groups. Afterwards the text box shows the raid as it now is, with the players who are not in the raid still on the list, and with auto-save on, the selected boss keeps it.
- **Invite missing** invites everyone on the list who is not in the raid yet.
- Names match regardless of case and accents, so `Majestic` finds `Májestíc`. Write `Name-Realm` when two players share a name.
- Requires raid leader or assistant to move players.

#### Auto

**Auto** (or `/raidnight auto`) balances groups 1–4 by role. Groups 1+2 and 3+4 are two halves, and each half gets the same share of tanks, healers, melee and ranged, as close as the raid allows. Groups 5–8 are left alone, so a bench stays a bench. The result goes into the text box and the raid is sorted by it; with auto-save on, the selected boss keeps it. Players on the list who are not in the raid stay on it: in their own group if Auto left room there, otherwise in the first group with room.

```
20 players: 2 tanks, 4 healers, 7 melee, 7 ranged

Group 1: T H M R R     Group 3: T H M M R
Group 2: H M M R R     Group 4: H M M R R
```

Tanks and healers come from the raid role. Melee or ranged comes from the class, except for Hunters, Shamans, Druids and Demon Hunters, whose spec is inspected. Specs are refreshed in the background during the session, also when someone changes spec. Anyone who can't be inspected is guessed from their class, and the chat says who.

#### Boss layouts

A row of boss icons at the top of the window shows the bosses of the current raid tier, read from the Encounter Journal. Pick the raid in the dropdown; it starts on the raid you are in.

- Click a boss to load its saved layout into the text box.
- The boss you pulled last is selected automatically, also after a `/reload`. Click another boss to choose it instead.
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

`/rn` works as a short form of `/raidnight`, e.g. `/rn auto`.

| Command | Action |
|---|---|
| `/raidnight` | Open or close the window |
| `/raidnight apply` | Sort by the last pasted layout (handy in a macro) |
| `/raidnight auto` | Balance groups 1–4 by role and sort |
| `/raidnight invite` | Invite players on the list who are not in the raid |
| `/raidnight stop` | Stop a sort in progress |
