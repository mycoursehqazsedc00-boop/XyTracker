# XyTracker (Tmog SR Tool)

A vanilla WoW (1.12) raid addon for running **Soft Reserve (SR) + DKP** loot
sessions. Members submit item links in raid chat, the raid leader gets a
live sortable list of who wants what and their current DKP, and everyone
can hover an item to see who's SR'd it — with a real item tooltip, not
plain text.

Works on English and Chinese clients. No dependencies required; a couple
of features get better with [ClassicAPI](https://github.com/brues-code/ClassicAPI)
installed (see below).

## Features

- **SR submission** — members type an item link in raid/party chat; the
  leader's list picks it up automatically.
- **DKP tracking** — per-member DKP with +/- buttons, auto-deduct on loot
  (configurable by item quality), and bid tracking (type `1`-`4` in raid
  chat).
- **Hoverable SR list** — hovering a member's SR entry pops up the actual
  item tooltip (icon, stats, everything), not just colored text.
- **Auto-announce** — when a qualifying item link (green/blue/purple/orange,
  configurable) appears in raid chat, the leader's client automatically
  reports who SR'd it and their DKP.
- **Leader ↔ member sync** — the leader's data is the source of truth;
  members' addons request and receive it automatically over the addon
  channel.
- **Roll monitor**, **wish broadcast**, **CSV export**, and a **raid
  declaration** (rules/notes) that can be posted to raid warning line by
  line.
- **Auto-refresh on raid join/leave** — stale data from last week's raid
  doesn't linger; see [Client-mod fixes](#client-mod-fixes-used) below.

## Client-mod fixes used

The addon runs standalone on plain vanilla 1.12. These two features
specifically use extensions from **[ClassicAPI v1.12.7](https://github.com/brues-code/ClassicAPI/releases/tag/v1.12.7)**
when it's installed, and fall back to plain-vanilla behavior when it isn't
— nothing breaks either way.

| Feature | Vanilla-only behavior | With ClassicAPI |
|---|---|---|
| Hover tooltip on the SR list | `GameTooltip:SetHyperlink(...)` — can show "Retrieving item information" if the client hasn't cached that item yet | `GameTooltip:SetItemByID(itemID)` + `C_Item.IsItemDataCachedByID` / `C_Item.RequestLoadItemDataByID` to warm the item cache first |
| "Who else SR'd this?" line in AtlasLoot / world / chat-link tooltips | Matches by the item's **display name** (two items that happen to share a name can collide) | Uses `GameTooltip:GetItem()` to read the tooltip's real **itemID** and matches on that instead |

Nothing else in the addon currently calls into ClassicAPI, SuperWoW,
Nampower, UnitXP_SP3, WeirdUtils, or VanillaHelpers — those are on the
project's radar for future work, not wired in yet. If you add anything
that depends on one of them, please note it in this table and add a
runtime `if SomeGlobal then ... end` guard the way the two rows above do,
so the addon keeps working for people who don't have it installed.

## How it works

- **SR data** lives in a single Lua table (`XyArray`), one entry per raid
  member: `{ name, class, xy (their SR'd item link(s)), dkp }`.
- **Addon-channel protocol** (unchanged across versions — old and new
  copies of the addon can sync with each other):
  - `XY_START` — leader broadcasts that SR is open.
  - `XY_SYNC_NEW` — anyone requests a full resync (sent automatically on
    joining a raid, and on load).
  - `XY_SYNC` — leader replies with the full member list.
- **Raid join/leave detection** is driven by the `RAID_ROSTER_UPDATE`
  event rather than matching localized system-chat text, so it behaves
  the same on English and Chinese clients: leaving clears/prompts to
  clear your local data, joining wipes stale data and pulls a fresh list
  from whoever's currently leading.
- **Auto-deduct** parses the loot roll message and the player's last
  raid-chat bid number to subtract DKP automatically (leader only).

## Installation

1.(Optional, recommended) Install [ClassicAPI v1.12.7](https://github.com/brues-code/ClassicAPI/releases/tag/v1.12.7)
   for the improved tooltips described above.
   2. Restart the client (or `/reload`) and enable **XyTracker** on the
   AddOns screen.

## Usage

- `/xyt` (or `/Xytrack`) — toggle the main window.

**As raid leader:**
1. Open the window and click **Start** — this announces SR is open and
   lets members' clients auto-sync to you.
2. Members SR by pasting item link(s) in raid chat.
3. Use the **+ / -** buttons next to a member's DKP to adjust it, or let
   auto-deduct handle it on loot.
4. **Stop** to lock SR, **Clear** to wipe the list for a new raid,
   **Refresh** to pick up any new raid joiners, **Export** for a CSV-style
   dump, **Broadcast** to read the current list out to raid chat.
5. Optional toggles (checkboxes in the window): auto-announce on
   item-link post, which item qualities to include (green/blue/purple —
   orange always announces), auto-clear on leaving raid, auto-reset DKP
   to default on refresh.

**As a raid member:**
- Paste your item link(s) in raid chat to SR them.
- Hover your name's row in the list (or anyone else's) to see the actual
  item tooltip for what they SR'd.
- Hover an item elsewhere (loot, AtlasLoot, a chat link) to see who else
  has SR'd it.
- Whisper `cxxy` to the raid leader's addon to get your current SR/DKP
  whispered back to you.

## Configuration reference

| Option | Where | Effect |
|---|---|---|
| Auto-announce | checkbox | Leader's client announces SR status when a qualifying item link appears in raid chat |
| Green / Blue / Purple mode | checkboxes | Which item qualities count as "qualifying" for auto-announce and auto-deduct (orange always counts) |
| Auto-min DKP | checkbox | Auto-deduct DKP from the winner when loot is distributed |
| Clear on leave | checkbox | Prompt to clear all SR data when you leave the raid group |

## Compatibility notes

- Requires WoW 1.12 (Interface 11200).
- SavedVariables: `XyArray`, `DefaultDKP`, `XyTrackerOptions`.
- The addon-channel protocol (`XY_START` / `XY_SYNC_NEW` / `XY_SYNC`) is
  unchanged from earlier versions, so mixed old/new copies in the same
  raid still sync correctly with each other.
