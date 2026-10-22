**Raidnight Helper** is the in-game companion addon for the [Raidnight](https://raidnight.io/) website. It is built to grow: each tool for raid night lives in the same addon.

The in-game interface follows the language of the game client: English, German, French, Spanish, Italian, Portuguese, Russian, Korean and Chinese (Simplified and Traditional). Text without a translation shows in English.

---

## Features

### Group sorting
Paste a group layout from the website and the raid sorts itself into the planned groups.

- Open the window with `/raidnight` (or `/rn`) and paste the layout into the field at the top with Ctrl+V. The groups fill in at once.
- The layout shows as groups 1–8, with 1–4 above 5–8. Drag a name onto another name to swap the two, onto an empty slot to move it there, or to **Not on list** to take it off the list. Raid members who are not on the list wait in that column and can be dragged into a group. Names show in class colours with a role icon (tank, healer, melee or ranged), and grey while the player is not in the raid. A name that is in another group in the raid shows that group's number in orange. In a raid, the players you drag move in the raid at once, the same way Sort raid moves them (leader or assistant, and after combat when in combat); everyone else stays put until **Sort raid**, apart from someone who has to make room in a full group. Dragging while a sort runs adds the move to it.
- Accepts plain text or the website's `RS1:` code.
- A live preview shows how many players are in the wrong group, who on the list is not in the raid, and which names match more than one player.
- **Sort raid** moves players one at a time and waits for each move to land before the next. Two players who are to trade groups swap in one move. Sorting pauses in combat and continues when combat ends. If the game rejects a move, that player stays put, the rest are sorted, and the summary names them.
- **Locks**: click the lock on a name to lock or unlock that player. Sort raid never puts a locked player in the [groups that play](#groups-that-play) (groups 1–4 in a raid of 20). One who stands in those groups stays there, unless the list needs the slot; then they move to a group after them, where they are sorted like anyone else. **Balance** never moves a locked player. While there is a list, everyone not on it starts locked, so a helper on the sidelines is not pulled into the raid. Dragging a locked player still moves them, and **Auto** unlocks everyone. Locks last until you leave the raid or reload.
- **Fill open slots with players not on the list** (on by default): players on the list keep their groups, and unlocked players who are not on it take the open slots in the groups that play by role and class, with the same rules as Auto. Slots of list players who are not in the raid, or whose name matches more than one player, stay free for them; anyone left over goes to the free groups. Afterwards the layout shows the raid as it now is, with the players who are not in the raid still on the list, and with auto-save on, the selected boss keeps it.
- **Undo** brings back the layout, the locks and, with auto-save on, the boss's saved layout from before Auto, Balance or filling open slots last changed them. The raid stays as it is until **Sort raid**.
- **Invite missing** invites everyone on the list who is not in the raid yet.
- Names match regardless of case and accents, so `Ravena` finds `Ravéna`. Write `Name-Realm` when two players share a name.
- Requires raid leader or assistant to move players.

#### Groups that play

Auto, Balance, locks and filling open slots work on the groups that play, split into two halves. How many groups play follows the size of the raid and the raid you are in:

| Raid | Groups that play | Halves |
|---|---|---|
| Up to 20 players, or Mythic | 1–4 | 1+2 and 3+4 |
| 21 or more in Mythic flex (up to 25 players) | 1–5 | 1–3 and 4–5 |
| 21 or more in Normal or Heroic, or outside a raid | 1–6 | 1–3 and 4–6 |

The groups after them are the bench. Outside a raid the addon can't tell Mythic from Normal or Heroic, so it plans for up to 30 players; inside, it knows how many the raid lets in.

#### Auto

**Auto** (or `/raidnight auto`) picks who plays from the whole raid and balances the groups that play by role. The players the list puts in those groups come first; the slots left go to the others by role, those already in them first. Players the list puts in a later group stay out, and everyone without a slot waits in the groups after the ones that play. Each half gets the same share of tanks, healers, melee and ranged, as close as the raid allows; in Mythic flex, where groups 4–5 can't take half the raid, each half's share follows its size. The halves themselves are as even as the groups allow: 9 and 9 with 18 players, 13 and 12 with 25 in groups 1–6, and 15 and 10 with 25 in Mythic flex. Damage dealers of the same class are split between the halves too, as far as the melee and ranged balance allows: 2 Hunters means 1 in each half. Only the half matters, so Auto moves as few players as it can: a player stays in their own group when it is in the right half, and players trade halves when that saves a move without leaving any role or class less evenly split. Auto unlocks everyone. The result becomes the layout and the raid is sorted by it; with auto-save on, the selected boss keeps it. Players on the list who are not in the raid stay on it: in their own group if Auto left room there, otherwise in the first group with room.

```
20 players: 2 tanks, 4 healers, 7 melee, 7 ranged

Group 1: T H M R R     Group 3: T H M M R
Group 2: H M M R R     Group 4: H M M R R
```

Tanks and healers come from the raid role. Melee or ranged comes from the class, except for Hunters, Shamans, Druids and Demon Hunters, whose spec is inspected. Specs are refreshed in the background during the session, also when someone changes spec. Anyone who can't be inspected is guessed from their class, and the chat says who.

#### Balance

**Balance** (or `/raidnight balance`) evens out the damage of the two halves of the [groups that play](#groups-that-play), using the damage each damage dealer did in the last boss pull (kill or wipe), read from the game's damage meter. After a `/reload` it still finds that pull while the damage meter has it; otherwise it takes the newest fight in the meter, and the chat says which. Each half's goal is its share of the players: half and half when the halves are the same size, 60% and 40% with 15 and 10 players. Only melee and ranged count, and only they move: two players in opposite halves trade places, until the halves are within 5% of their goal. Tanks, healers, locked players and the groups after the ones that play stay where they are.

Auto's rules hold as far as they can. Balance first looks for swaps of melee for melee and ranged for ranged that keep each class as evenly split as before; then swaps of the same role, even if a class ends up less evenly split; and only then a melee for a ranged. Within that, it moves as few players as it can, and nobody moves twice. If the halves can't get within 5%, it gets them as close as it can.

The chat shows each half's share of the damage before and after, the goal when the halves differ in size, and who trades places. A damage dealer the meter has no damage for (for example someone who joined after the pull) counts as an average one and stays put. The result becomes the layout and the raid is sorted by it; with auto-save on, the selected boss keeps it. Balance only does something when you press it. The damage meter's numbers are hidden in combat, so it only runs out of combat.

#### Boss layouts

A row of boss icons at the top of the window shows the bosses of the current raid tier, read from the Encounter Journal. Pick the raid in the dropdown; it starts on the raid you are in.

- Click a boss to load its saved layout into the groups.
- The boss you pulled last is selected automatically, also after a `/reload`. Click another boss to choose it instead.
- **Save** stores the current layout under the selected boss. **Delete** removes it.
- Faded icons have nothing saved yet. Hover an icon to see when its layout was saved.
- With **Save the raid's groups to the boss on pull** checked (the default), every pull stores the raid's groups as they are under that boss, so the next click on it brings back the groups from the last pull. Raid Finder pulls are skipped.
- Layouts are stored account-wide in WoW's saved variables, so addon updates keep them.

#### Text format

```
Group 1: Brannoc, Elowyn, Fenwick, Isolde, Torvald
Group 2: Ashlyn, Corvain, Dúnmir, Ravéna, Thessaly
```

Names can also go one per line under a `Group N` line, and `Gruppe`, `G1` and `1.` work as group headers too.

#### Commands

`/rn` works as a short form of `/raidnight`, e.g. `/rn auto`.

| Command | Action |
|---|---|
| `/raidnight` | Open or close the window |
| `/raidnight apply` | Sort by the last pasted layout (handy in a macro) |
| `/raidnight auto` | Pick who plays from the whole raid, balance the groups that play by role, and sort |
| `/raidnight balance` | Even out the damage of the two halves from the last boss pull, and sort |
| `/raidnight invite` | Invite players on the list who are not in the raid |
| `/raidnight stop` | Stop a sort in progress |
