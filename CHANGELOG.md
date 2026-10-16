## [1.0.0]

### Added
- **Group sorting** Paste a group layout from the Raidnight website (plain text or an `RS1:` code) and the raid sorts itself into the planned groups. The layout shows as groups 1–8 with class colours and role icons, and dragging a name to another group moves that player in the raid too. Names in another group in the raid show that group's number. Includes a live preview, inviting players who are missing, and an option to fill open slots with players who are not on the list, by role and class. A move the game rejects is skipped, and the rest of the raid is still sorted. Open it with `/raidnight` or `/rn`.
- **Locks** Click the lock on a name to keep that player out of groups 1–4 when sorting, and in place when balancing. Players who are not on the list start locked.
- **Undo** Brings back the layout from before Auto, Balance or filling open slots changed it.
- **Balance** Evens out the damage of groups 1+2 and 3+4 by the last boss pull (or else the newest fight), read from the game's damage meter, by swapping melee and ranged between the halves while keeping Auto's rules as far as possible.
- **Auto** Picks groups 1–4 from the whole raid, the list's players first, and balances them by role: groups 1+2 and 3+4 each get the same share of tanks, healers, melee and ranged, and damage dealers of the same class are split between them. Only the half matters, so Auto moves as few players as it can. Melee or ranged specs of Hunters, Shamans, Druids and Demon Hunters are inspected and kept up to date during the session.
- **Localization** The interface follows the language of the game client, with English as the fallback.
- **Boss layouts** A row of boss icons from the current raid tier at the top of the window. Save a layout for each boss and load it again with one click. Optionally, every pull saves the raid's groups under that boss automatically.
