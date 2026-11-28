# XyTracker (Tmog SR Tool)

A vanilla WoW (1.12) raid addon for running **Soft Reserve (SR) + DKP** loot
sessions. Members submit `XY [itemlink]` in raid chat, the raid leader gets a
live sortable list of who wants what and their current DKP, and everyone
can hover an item to see who's SR'd it — with a real item tooltip, not
plain text.

Works on English and Chinese clients. No DLL dependencies are required;
optional enhancements activate automatically when **ClassicAPI** or
**UnitXP SP3** is installed.

## Optional Client DLL Mods

All client-mod integrations are feature-detected at runtime and fall back
cleanly to stock WoW 1.12 behavior when absent:

| Mod | Feature | Vanilla-only behavior | With Mod |
|---|---|---|---|
| **ClassicAPI** | Hover tooltip on the SR list | `GameTooltip:SetHyperlink(...)` — can show `"Retrieving item information"` if uncached | `GameTooltip:SetItemByID(itemID)` + `C_Item.IsItemDataCachedByID` / `C_Item.RequestLoadItemDataByID` |
| **ClassicAPI** | Sync cache warm-up | Items cache lazily on hover | `C_Item.RequestLoadItemDataByID` pre-warms all SR'd `itemID`s as `XY_SYNC` packets arrive |
| **ClassicAPI** | "Who else SR'd this?" tooltip line | Matches by item display name | Uses `GameTooltip:GetItem()` to match by exact `itemID` (no name collisions) |
| **UnitXP SP3** | Taskbar flash notifications | No OS taskbar flash | Calls `UnitXP("notify", "taskbarIcon")` when the leader starts SR (`XY_START`) or when `RollMonitor` finishes |

## Features

- **Admin `XY [itemlink]` parsing & member sync-only:** When you are the active SR manager (`IsLeader`), raid-chat SR submissions require the `XY ` prefix (case-insensitive) and fall back to link-color quality detection if the item isn't cached yet, or plain-text `[Item]` fallback when a player types `XY myItem` without an item link. Non-admin members do not parse chat and stay synced automatically to the leader's list.
- **Auto-scan boss loot (`LOOT_OPENED`):** When `Auto-announce` is enabled, opening a boss/chest loot window automatically checks qualifying items and announces who SR'd them (with a 3s debounce).
- **Class-colored SR list & Right-Click row menu:** Member names and classes are colored by class. Right-clicking any row opens a quick menu (`Query SR to Raid`, `Whisper Remind SR`, plus `+1 DKP`, `-1 DKP`, and `Clear SR` for the leader).
- **DKP tracking & Auto-Deduct:** Per-member DKP with `+`/`-` buttons, configurable default DKP (`Init DKP`), bid tracking (`1`-`4` in raid chat), and automatic DKP deduction on loot (supports both enUS and zhCN loot messages).
- **Hoverable SR tooltips:** Hovering a member's row shows the full item tooltip; hovering items in loot, AtlasLoot, or chat links shows everyone who SR'd that item and their DKP.
- **Roll Monitor:** Tracks `/roll` (1-100) on both enUS and zhCN clients with live countdown on the window title, scrollable list (`FauxScrollFrame`), automatic end-of-timer winner announcement, and optional UnitXP SP3 taskbar flash.
- **Wish broadcast, scrollable CSV export & multiline Raid Declaration:** Broadcast sorted SR entries to raid chat, export the raid list inside a scrollable window (`XyExportScrollFrame`), and write/announce multiline raid rules line-by-line to Raid Warning.
- **Movable Minimap button:** Left-click to toggle the window; Right-drag to reposition around the minimap (saved in `XyTrackerOptions.minimapAngle`).
- **Auto-refresh on raid join/leave:** Driven by `RAID_ROSTER_UPDATE` (locale-independent) so stale data from previous raids is cleared and fresh data is requested automatically.

## What Was Added / Improved

- **Strict Lua 5.0 compatibility:** Replaced all `string.gmatch` calls with `string.gfind` so the addon runs without ClassicAPI.
- **Lifecycle & nil safety:** Moved `SavedVariables` initialization from `OnLoad` to `VARIABLES_LOADED` / `PLAYER_LOGIN`, guarded `DefaultDKP`, `getXyInfo`, tooltip `GetText()`, and `GetNumRaidMembers() > 0` checks.
- **UI & XML fixes:** Removed erroneous `virtual="true"` from the 7 option checkboxes, fixed `XyTrackerFrame` anchors and `StatusText` overlap, enabled multiline `Enter` newlines in `XyTrackerDeclarationLargeEditBox`, and added `XyExportScrollFrame`.
- **Sync & protocol safety:** Preserved 100% wire compatibility (`XY_START`, `XY_SYNC_NEW`, `XY_SYNC`), debounced `XY_SYNC` list redraws (`0.1s`), and trimmed oversized `XY_SYNC` payloads to `<= 254` bytes without breaking `,s=<dkp>`.
- **QoL & client mods:** Added `LOOT_OPENED` boss loot auto-scan, class-colored rows, Right-Click row context menu, live `RollMonitor` countdown, Right-drag minimap button, ClassicAPI `C_Item` sync warm-up, and UnitXP SP3 taskbar notifications.

## Usage

- `/xyt` (or `/Xytrack`) — toggle the main window.

**As raid leader (admin):**
1. Open the window and click **Start** — announces SR is open and syncs members.
2. Members type `XY [itemlink]` in raid chat to submit their SR.
3. Use `+` / `-` buttons, Right-Click a row, or **Auto Deduct** to manage DKP.
4. **Stop** to lock SR, **Reset** to wipe the list, **Refresh** to add new joiners, **Export SR** for a scrollable dump, **Broadcast SR** to post to raid chat.

**As a raid member (non-admin):**
- Type `XY [itemlink]` in raid chat to submit your SR.
- Your addon stays synced to the leader via `XY_SYNC` without filtering chat locally.
- Whisper `cxxy` to the leader to receive your current SR and DKP.

## Configuration Reference

| Option | Where | Effect |
|---|---|---|
| `XY-only mode` | checkbox | Toggle XY-only mode flag |
| `Duplicate SR Alert & Auto Announce` | checkbox | Leader announces duplicate SRs and qualifying item links in raid chat / on `LOOT_OPENED` |
| `Green / Blue / Purple only` | checkboxes | Item qualities eligible for auto-announce and auto-deduct (orange always qualifies) |
| `Auto Deduct` | checkbox | Auto-deduct DKP from the winner on loot |
| `Clear on Leave` | checkbox | Prompt to clear SR data when leaving a raid |

## Compatibility Notes

- Requires WoW 1.12 (Interface `11200`).
- SavedVariables: `XyArray`, `DefaultDKP`, `XyTrackerOptions`.
- Wire protocol (`XY_START`, `XY_SYNC_NEW`, `XY_SYNC`) is 100% compatible with earlier versions.
