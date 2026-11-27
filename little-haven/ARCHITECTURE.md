# Little Haven: Feasibility, Architecture and Roadmap

**Status:** proposal for approval. No system changes have been made.
**Date:** 2026-11-27

---

## 0. What was and was not inspected

| Item | Status |
|---|---|
| Existing Little Haven project | **None found.** The only repository available to this session is `Moviecation`, a single-file movie watchlist web app (`index.html`). It has no Little Haven code. If Little Haven lives elsewhere (another repo, a Playnite theme folder, local files), point me to it. |
| Hardware, Windows configuration, power states, controller, displays, installed storefronts | **Not inspected.** This session runs in a cloud Linux container and no Windows machine is attached. |
| Substitute | `tools/inventory.ps1` is a **read-only** PowerShell inventory script that collects everything Phase 0 needs (see §7). Running it on the PC, or attaching the PC to a session via Remote Control, closes this gap. |

Everything below is based on the hardware you listed plus research. Items marked **[P0]** depend on measurements on your actual machine.

---

## 1. Landscape: what already exists (as of Nov 2026)

| Option | What it gives | Why it is not enough alone |
|---|---|---|
| **Windows 11 Xbox mode** (formerly "Full Screen Experience"; rolling out to all Windows 11 PCs, desktops included, since 30 Apr 2026) | Microsoft-supported controller shell. Can boot straight into it, skips loading most of the desktop, Xbox button → home, Game Bar quick settings, a combined library of Game Pass titles and installed games from other stores. Anti-cheat safe because it is Windows itself. | Shows only *installed* games from non-Xbox stores. No cross-store purchasing, price comparison, wishlist, maintenance orchestration, presets or uninstalled-game installs for other stores. Not extensible. Reports of unreliable sleep/resume early in the rollout. |
| **Steam Big Picture** | The best controller UI and Steam Input. Excellent Steam store, downloads and install flow. | Other stores only as manual "non-Steam shortcuts" with no ownership sync. Grabs the Xbox button. Injects its overlay into anything it launches. |
| **Playnite 10** (stable, still shipping monthly) | Mature library plugins for all six stores, MIT-licensed extensions, a fullscreen mode. | Launcher, not platform. No system services, maintenance or store aggregation. Fullscreen mode is a theme layer on top of WPF desktop software. **Playnite 11** is a closed-source rewrite (source stays private until beta) with no firm date, so it cannot be a planned foundation. |
| **Heroic / Legendary / gogdl** | Open-source Epic and GOG clients that can own downloads, giving a real download queue. | Reverse-engineered, outside Epic's supported path. Breaks when Epic changes things. Not a dependency for anti-cheat titles. |
| **IsThereAnyDeal API** | Official, keyed API: price history and current deals across Steam, Epic, GOG, Microsoft, EA, Ubisoft and others, shop-ID mapping, waitlist (wishlist) sync via OAuth. | Subscription catalog coverage (Game Pass, EA Play, Ubisoft+) is unverified. Needs a supplementary source. |

**Conclusion:** no single product meets the goal. The mature pieces each cover a slice. Little Haven should be a **standalone, modular platform** that orchestrates the official launchers, which stay the source of truth for DRM, cloud saves, achievements and anti-cheat, plus Windows' own power, display and update services. It reuses mature components and reimplements only the glue. Playnite does not remain the foundation, though its MIT plugin code is a valuable reference for store connectors.

---

## 2. Requirement feasibility matrix

Legend: ✅ fully achievable · 🟡 partially achievable (closest alternative given) · ⛔ blocked (no supported path; alternative given) · **[P0]** depends on on-machine testing

### 2.1 Unified game library

| Requirement | Verdict | Notes / closest alternative |
|---|---|---|
| Sync owned games: Steam | ✅ | Official Steam Web API `GetOwnedGames` (API key + SteamID) plus local `appmanifest_*.acf`. |
| Sync owned games: GOG | ✅/🟡 | GOG's OAuth library endpoints (used by Galaxy, community-documented) plus the local registry. Stable for years but not formally published. |
| Sync owned games: Epic, Xbox/Game Pass, EA, Ubisoft | 🟡 | **No official public ownership APIs.** The workable path is the same one Playnite has used for years: sign in with your own account, then read your own library from the store's internal endpoints, **read-only**. Installed state always comes from the official launcher's local manifests, so it does not depend on those endpoints. Risk: endpoints change and connectors need maintenance, which is why connectors are isolated modules. |
| Installed and uninstalled together | ✅ | Merge of owned + installed per connector, de-duplicated by a cross-store game identity (ITAD/IGDB IDs). |
| Launch | ✅ | Always through the owning launcher's URI or protocol (`steam://rungameid/`, `com.epicgames.launcher://apps/…?action=launch`, `shell:AppsFolder\<AUMID>` for Xbox, `link2ea://`, `uplay://launch/`, Galaxy `/command=runGame`). |
| Install | 🟡 | Little Haven can *start* installs (`steam://install/<id>`, the Epic `action=install` URI, the Xbox app product page). Each launcher then shows its **own confirmation dialog**. Steam's is controller-friendly. Epic, EA, Ubisoft and GOG dialogs are mouse-oriented. Alternative: Little Haven's **controller-as-pointer** mode (SendInput, active only outside games) plus a focus manager that brings the dialog forward and returns home when done. |
| Update | 🟡 | Launchers update their own games. Little Haven *reports* state from manifests and *schedules* it (§2.3). It cannot force-update arbitrary stores. |
| Uninstall | 🟡 | Steam ✅ (`steam://uninstall/`). Others go through their launcher UI, routed the same way as installs. |
| Detect new purchases | ✅/🟡 | Poll owned lists on wake, after any store visit, and every few hours. Instant for Steam and GOG, best-effort for the rest. |
| Preserve cloud saves, achievements, DLC, multiplayer | ✅ | Guaranteed by a hard rule: **never launch an executable directly**. Always launch through the owning launcher. |

### 2.2 Universal storefront

| Requirement | Verdict | Notes / closest alternative |
|---|---|---|
| Browse across stores in one UI | 🟡 | Little Haven's own browse and search UI, built on catalog metadata (IGDB/ITAD) with a deep link into each store's official page. Store pages are shown in the store's own client (best) or an embedded WebView2. |
| Compare prices and discounts | ✅ | ITAD API, regional pricing, historical lows. |
| Compare editions | 🟡 | ITAD lists per-store products. Edition matching (Standard vs Deluxe vs bundle) is heuristic, so the UI shows the store's own edition names side by side. |
| Subscription availability | 🟡 | Game Pass: Microsoft's public catalog feeds (unofficial but long-stable). EA Play / Ubisoft+: verify ITAD coverage in Phase 5; fall back to periodic catalog snapshots. |
| Identify already-owned | ✅ | Join the store catalog against the unified library. |
| Universal wishlist | ✅ | Little Haven holds the master wishlist locally, synced two-way with the ITAD waitlist (official OAuth). It imports the Steam wishlist read-only. Price-drop alerts. |
| One seamless purchase | ⛔ (unified checkout) → 🟡 | **No store allows third-party checkout**, and payment details must never pass through Little Haven. Closest reliable alternative: a **"Buy" action that opens the exact product page in that store's own checkout**, in a controller-navigable surface: Steam Big Picture store, Xbox app / Microsoft Store, Epic launcher, GOG Galaxy, EA app, Ubisoft Connect. Little Haven waits, then re-syncs ownership and offers "Install now". |
| Auto-sync purchases to library | ✅ | Triggered refresh on return from any store surface. |

### 2.3 Automatic maintenance

| Requirement | Verdict | Notes / closest alternative |
|---|---|---|
| Windows updates coordinated | ✅ | Windows Update Agent API, active hours, pause during play, install and restart only in the maintenance window. |
| Driver updates (NVIDIA) | 🟡 | The NVIDIA app has no public automation API. Little Haven *detects* new Game Ready drivers and asks you. On approval it runs NVIDIA's own installer silently in the maintenance window, with a restore point first. **Never automatic without approval.** |
| Launcher and game updates | 🟡 | Steam: its built-in download-window schedule (set once). Others: launchers are left running during the maintenance window so their auto-updaters run. |
| Maintenance during idle periods | ✅ | Scheduled task with "wake the computer to run this task" at e.g. 04:00 → update pass → back to sleep. Needs wake timers enabled **[P0]**. |
| Never interrupt a game | ✅ | Session state machine: while a game runs, Windows Update is paused, no launcher is foregrounded and no notifications are shown. |
| Minimize authentication prompts | 🟡 | Token lifetimes are set by each store. Alternative: an **Accounts health** page that checks every connector on wake and asks for re-login *in Little Haven, before you pick a game*, not mid-launch. |
| Unified download/update queue | ⛔ across launchers → 🟡 | Every launcher owns its downloader and there is no cross-launcher control API. Closest alternative: a **unified download board** that reads progress from each launcher's manifests, plus a policy that Little Haven starts installs one launcher at a time. Optional upgrade, not recommended: let Legendary/gogdl own Epic and GOG downloads for a real queue. That carries Terms-of-Service and breakage risk and must never be used for anti-cheat titles. |

### 2.4 Performance

| Requirement | Verdict | Notes |
|---|---|---|
| Native Windows performance | ✅ | No injection, hooks, kernel drivers or shell replacement. While a game runs the UI process suspends rendering (WebView2 `TrySuspend`) and the agent idles on a low-frequency input poll. Target: within the measurement noise of a no-Little-Haven baseline. |
| Fortnite and anti-cheat compatibility | ✅ | Little Haven never touches game processes or memory, never loads DLLs into them, and installs no drivers. Games launch via their launchers. See §3. |
| HDR, VRR, DLSS, high refresh | ✅ | Native. Little Haven can toggle Windows HDR and refresh rate through the documented DisplayConfig API and leaves G-Sync and DLSS to driver and game. |
| Recommend/apply graphics settings | 🟡 | **Driver-level, fully automatic:** NVAPI driver-settings profiles per game (G-Sync on, VSync on in driver, frame cap ≈ 225 fps for a 240 Hz panel, Low Latency / Reflex preference). **Game-level:** curated config adapters for selected games, applied only while the game is closed and only to user-config files (never anti-cheat-protected files). Everything else gets a recommendation card. The NVIDIA app's "Optimize" has no public API, so it is linked, not automated. |
| Quality / Balanced / Performance presets | 🟡 | Each preset is a bundle: driver profile + DLSS mode + game adapter where one exists + target frame rate (Quality ≈ 120, Balanced ≈ 165, Performance ≈ 225 at 1440p). Universal for driver-level settings, per-game for in-game settings. |
| Low background consumption | ✅ | Budgets with acceptance tests (§5). Launchers not needed at boot are deferred, except Steam, which must run for Steam DRM. |

### 2.5 Console-level system controls

| Requirement | Verdict | Notes / closest alternative |
|---|---|---|
| **Wake from the controller** | 🟡 **[P0]**, the biggest risk | Xbox-button wake from true sleep (S3) is **not something Windows guarantees**. Reports are mixed. Bluetooth wake is often greyed out in Device Manager. The Xbox Wireless Adapter (USB dongle) works for some people, especially on USB 3 ports with USB wake enabled in BIOS. Phase 0 tests these paths on your board, in order: **(A)** Xbox Wireless Adapter + BIOS USB wake from S3. **(B)** Bluetooth adapter wake. **(C)** "Console standby": S0 with displays off, the GPU idling, the controller still connected, and the Xbox button handled by Little Haven, which gives instant on. The cost is idle power (tens of watts, measured in P0). **(D)** A purpose-built USB wake device: a small microcontroller that listens for the controller and issues a standard USB remote-wake. This works with any board but needs hardware. Recommendation: A if it passes 20/20 cycles, otherwise C with an automatic fall into real sleep after a configurable idle time. |
| Monitor wakes and sleeps automatically | ✅ **[P0]** | Follows the video signal. Verify that your OLED wakes on DisplayPort/HDMI signal from standby. Little Haven never cuts monitor power, so OLED pixel-refresh cycles still run in standby. |
| No sign-in prompt on wake | 🟡 **requires your decision** | Options: (1) Windows Hello face sign-in with an IR camera: hands-free and secure. (2) "Require sign-in after sleep: Never" plus autologon at boot (Sysinternals Autologon stores the secret LSA-encrypted). This is convenient but anyone at the PC gets in. (3) Keep the PIN and enter it on the controller via the on-screen keyboard. **Security-relevant: nothing is changed without your approval.** |
| Controller-friendly network, audio, Bluetooth, display, storage | ✅/🟡 | Wi-Fi via the Native WLAN API ✅. Bluetooth pairing via Windows.Devices.Enumeration ✅. Display, HDR and refresh via DisplayConfig ✅. Storage free space and per-launcher library locations ✅. Moving games uses the launcher UI 🟡. Switching the audio output device has no documented API. The widely used `IPolicyConfig` interface works but is undocumented 🟡. Volume and mute are documented ✅. |
| Xbox button returns home | ✅ | Turn off Game Bar's "open with controller button" setting. Read the Guide button via XInput's extended state (undocumented but stable for more than 15 years; Steam and Playnite use it). Configure Steam so the button doesn't also open Big Picture. A short press opens the Little Haven overlay. A long press keeps the Windows power menu. Conflicts with Xbox mode's own use of the button, see decision D1. |
| Reliable launch, switch, close | ✅/🟡 | Launch tracking per launcher (process tree + launcher state). Close: graceful close request → controller confirmation → force-close only if the game hangs. Some anti-cheat-protected processes refuse external termination, so the fallback is the game's own quit or a launcher stop. **Switching** means closing one game and starting another. Suspend-and-resume of multiple games is not safe with anti-cheat titles. |
| Desktop only when requested | ✅ | Explorer stays the Windows shell, which is required for many launchers, so nothing is replaced. Little Haven runs fullscreen at sign-in with an auto-hidden taskbar. "Desktop mode" is a menu item, optionally behind a PIN. |

### 2.6 Reliability

| Requirement | Verdict | Notes |
|---|---|---|
| Recover from crashes, failed launches, expired auth, network loss | ✅ | Watchdog restarts the UI within 2 s. Launch timeouts with a diagnosis ("Epic needs sign-in", "Update required", "No network"). Offline mode uses cached library and art. |
| Controller-accessible troubleshooting | ✅ | Diagnostics page: connector health, last errors, restart a launcher, network test, "collect logs". |
| Safe recovery into normal Windows | ✅ | Three independent paths: (1) hold **View + Menu for 3 s** → desktop, handled by the agent and working even if the UI is dead. (2) **Ctrl+Alt+Del** always works because the shell is not replaced. (3) A "Little Haven disabled" boot flag: holding a combo during startup skips autostart. |
| No irreversible changes without approval | ✅ | Every system change goes through an **apply / revert** journal with a restore point before anything significant. Phase 0 is read-only. |

---

## 3. Storefront, DRM and anti-cheat constraints

| Store | Ownership source | Installed source | Launch | Install / uninstall | Purchase surface | Auth | Risk |
|---|---|---|---|---|---|---|---|
| Steam | Web API (official, key) | `libraryfolders.vdf`, `.acf` | `steam://rungameid/` | `steam://install/` / `steam://uninstall/` | Big Picture store | Steam client login (long-lived) | Low |
| Epic | Account library endpoints (unofficial, read-only) | Launcher `Manifests\*.item` | Launcher URI (`action=launch&silent=true`) | Launcher URI / launcher UI | Epic launcher | Launcher login + Little Haven connector token | Medium: endpoint churn |
| Xbox / PC Game Pass | Xbox Live title history (unofficial) + Game Pass catalog feed | `Get-AppxPackage`, `XboxGames` folders | `shell:AppsFolder\<AUMID>` | Xbox app product page | Xbox app / Microsoft Store | Microsoft account (already signed in) | Medium |
| EA | EA app account endpoints (unofficial) | Registry / EA app data | `link2ea://` (validate in P2) | EA app UI | EA app | EA account | Medium–High: EA changes often |
| Ubisoft | Local launcher cache (partial) | Registry `Launcher\Installs` | `uplay://launch/<id>/0` | Ubisoft Connect UI | Ubisoft Connect | Ubisoft account, frequent re-prompts | Medium |
| GOG | GOG OAuth library endpoints | Registry `GOG.com\Games` | Galaxy `/command=runGame` (keeps cloud saves & achievements) | Galaxy UI | Galaxy / web | GOG account | Low–Medium |

**Anti-cheat rules (non-negotiable design constraints):**
1. No DLL injection, overlay hooks, or memory reading/writing of game processes. The in-game "Xbox button" overlay is a separate top-level window shown **only when summoned**, so it never sits over the game during play and never affects independent-flip, VRR or latency.
2. No kernel drivers, and no virtual-controller or device-hiding drivers (ViGEm, HidHide). Some kernel anti-cheats (Vanguard, Javelin, Ricochet) react to these.
3. Controller-as-pointer (SendInput) is **disabled while a game has focus**.
4. Launch only via official launchers, so Easy Anti-Cheat and BattlEye (Fortnite), and each store's DRM, stay in their supported paths.
5. Respect platform requirements: several current titles require **TPM 2.0 + Secure Boot** (e.g. Valorant, recent Call of Duty, Battlefield 6). The inventory checks this.
6. Game config adapters edit only user-settings files while the game is closed (e.g. Fortnite's `GameUserSettings.ini`), never game binaries or protected data.

---

## 4. Proposed architecture

```
 ┌──────────────────────────── User session ─────────────────────────────┐
 │                                                                        │
 │  Haven Shell (UI)            Haven Agent (always on, tiny)             │
 │  .NET 8 host + WebView2      - Guide button / combo listener (XInput)  │
 │  - Home, Library, Store,     - Session state machine (Home/InGame/…)   │
 │    Downloads, Settings       - Game process tracking, close/switch     │
 │  - Suspends while in-game    - Overlay summon, focus manager           │
 │          ▲                   - Controller-as-pointer (off in games)    │
 │          │ JSON-RPC          - Watchdog for Shell; desktop escape      │
 │          ▼                                ▲                            │
 │  Haven Core (library + catalog)           │ named pipes (ACL'd)        │
 │  - SQLite: games, identities, art, wishlist                            │
 │  - Connector host ──► [Steam] [Epic] [Xbox] [EA] [Ubisoft] [GOG]        │
 │                        (each its own process, common contract)         │
 │  - Catalog: ITAD (prices, waitlist), IGDB/SteamGridDB (metadata, art), │
 │    Game Pass catalog                                                   │
 │  - Presets: NVAPI driver profiles + per-game config adapters           │
 └───────────────────────────────────────────┬────────────────────────────┘
                                             │
 ┌──────────── Haven Service (Windows service, LocalSystem, minimal) ─────┐
 │  Maintenance scheduler (wake timers) · Windows Update Agent control    │
 │  Driver install on approval · power policy · restore points ·          │
 │  change journal (apply / revert)                                       │
 └────────────────────────────────────────────────────────────────────────┘
      Windows: explorer shell kept · Xbox mode optional · official launchers
```

**Key choices**

- **Standalone app, not a shell replacement.** Replacing explorer breaks launchers, toasts and UWP/GDK games. Windows' Shell Launcher feature exists only on Enterprise/Education. A fullscreen app started at sign-in, with the taskbar hidden, gives the same experience safely.
- **Process separation:** UI (can crash), Agent (must never crash and stays tiny), Core and Connectors (network-bound, can break independently), Service (the only privileged piece, with the smallest possible surface). Each store connector is a separate module behind one contract: `GetOwned`, `GetInstalled`, `Launch`, `Install`, `Uninstall`, `GetDownloadState`, `AuthStatus`, `Watch`. A broken EA connector cannot take down Steam.
- **Stack:** C#/.NET 8 for everything that touches Win32 (XInput, DisplayConfig, NVAPI, Windows Update Agent, power, Bluetooth, audio). A WebView2 + TypeScript/React UI with spatial (D-pad) navigation. This gives fast iteration, and store pages and metadata are web content anyway. Alternative: WinUI 3, which has better native feel but slower UI iteration and weaker spatial-navigation tooling.
- **Reuse:** Playnite's MIT library extensions (auth flows, endpoint knowledge), ITAD, IGDB, SteamGridDB, NVAPI, Windows Update Agent, Steam Big Picture for Steam's own store and install flow, and Xbox mode as an optional fallback home.

**Little Haven vs. Xbox mode (decision D1):** Xbox mode and Little Haven both want to be "home" and both want the Xbox button. Recommendation: **Little Haven is home**, with Game Bar's controller button off and Xbox mode kept as a one-tap fallback console mode. Phase 0 still measures whether Xbox mode's "boot without desktop" saves meaningful resources, and whether Little Haven can run cleanly inside it as a companion. If it can, a hybrid (Xbox mode as shell, Little Haven for library, store and maintenance) becomes an option.

---

## 5. Phased roadmap with acceptance tests

| Phase | Scope | Acceptance tests (all must pass) |
|---|---|---|
| **P0 Discovery & spikes** (read-only + reversible tests) | Run `inventory.ps1`. Wake-path matrix (A–D). Monitor wake. Guide-button capture alongside Game Bar, Steam and Xbox mode. Xbox mode evaluation. Performance baseline. | Inventory report reviewed. Each wake path scored over **20 sleep/wake cycles** (pass ≥ 20/20, with the time from button to usable image recorded). Idle power measured for S0-display-off vs S3. Baseline: 3 games × 3 runs of PresentMon (avg fps, 1% lows, latency). |
| **P1 Smallest console prototype** (§6) | Agent + Shell + Steam/Epic/Xbox *installed* games + launch/close + home overlay + sleep + desktop escape | See §6. |
| **P2 Full library** | All six connectors, uninstalled games, install/uninstall routing, controller-as-pointer, purchase detection, Accounts health | Owned counts match each store's own client within ±0 for Steam/GOG and ≤ 2% for others. Install started from Little Haven completes for one game per store with zero keyboard/mouse. A new purchase appears within 5 min of returning from a store. |
| **P3 System controls** | Wi-Fi, Bluetooth pairing, audio out/volume, display/HDR/refresh, storage | Each task completes controller-only. HDR toggle round-trips with no display left in a bad state over 20 toggles. |
| **P4 Maintenance service** | Wake-timer window, Windows Update orchestration, driver detection + approval, launcher update window, change journal | 7 consecutive nights: maintenance runs, the system returns to sleep, **0 interruptions** during scripted 2-h game sessions, every change has a working revert. |
| **P5 Universal store & wishlist** | Browse/search, price compare, subscription flags, owned badges, wishlist + ITAD sync, Buy → store checkout | Prices match the store page for 20 sampled titles. Owned badges 100% correct on a 50-title sample. Buy → purchase → "Install now" in under 3 controller screens after checkout. |
| **P6 Performance presets** | NVAPI profiles, presets, config adapters for your top 5 games | Presets apply and revert cleanly. Frame-rate targets met within 10%. No anti-cheat warnings in 10 sessions per protected title. |
| **P7 Hardening** | Fault injection: kill UI, kill connectors, pull network, expire tokens, crash a game, failed driver install | Every scenario recovers to a usable home screen in under 10 s with a clear message, and the desktop escape works in all of them. 7-day soak: no keyboard/mouse touched. |

**Global non-regression budgets (tested every phase):** in-game fps and 1% lows within ±1% of the P0 baseline. Agent < 50 MB RAM and < 0.5% CPU while in-game. Shell suspended (≈ 0% GPU) while in-game. Cold boot to usable home < 25 s. Wake to usable home < 5 s on the chosen wake path.

---

## 6. Smallest functional prototype: "the couch loop"

The goal is to prove the *feel*, not the features:

1. Press the Xbox button → the PC wakes (chosen P0 path) → the monitor wakes → **Little Haven home** in under 5 s with no sign-in prompt (per decision D2).
2. Home shows **installed** games from Steam, Epic and Xbox, **including Fortnite**, with art.
3. A → the game launches through its launcher, with no launcher window left in the foreground.
4. Xbox button in-game → overlay: **Resume / Close game / Home / Sleep**.
5. Sleep → the system and monitor sleep. Wake → back home.
6. Hold View + Menu for 3 s at any point → normal Windows desktop.

**Acceptance:** 20 consecutive full loops, zero keyboard/mouse/power-button touches. Fortnite matches play online normally. In-game fps within ±1% of baseline. The UI killed mid-session restarts itself, and the game keeps running.

Not in the prototype: store, maintenance, uninstalled games, EA/Ubisoft/GOG, presets.

---

## 7. Decisions needed before implementation

| # | Decision | Recommendation |
|---|---|---|
| D1 | Home: Little Haven vs. Xbox mode vs. hybrid | Little Haven home, Xbox mode as fallback. Revisit after P0. |
| D2 | Sign-in on wake | Windows Hello face if you have or will add an IR camera. Otherwise your call between "no sign-in after sleep" and a PIN on the controller. |
| D3 | Sleep model | Decided by P0 data. Prefer real S3 with dongle wake, else console standby + timed deep sleep. |
| D4 | Unofficial read-only ownership endpoints for Epic, Xbox, EA, Ubisoft (own account only) | Accept, since there is no other way to show uninstalled games for those stores. Isolate them in connectors. |
| D5 | Legendary/gogdl-owned downloads | Decline for now. Official launchers only. |
| D6 | Stack (.NET 8 + WebView2) | Approve, or choose WinUI 3. |
| D7 | Repository | Create a dedicated `little-haven` repository. This branch of `Moviecation` holds only this proposal. |
| D8 | P0 access | Run `tools/inventory.ps1` and share the output, or attach the PC via Remote Control so P0 can be done directly. |

---

## Sources

- Xbox Wire, "Xbox Mode Begins Rolling Out to Players on Windows 11 PCs Today" (30 Apr 2026): https://news.xbox.com/en-us/2026/04/30/xbox-mode-pc-windows-11/
- Windows Experience Blog, Xbox full screen experience preview for PCs (24 Nov 2025): https://blogs.windows.com/windowsexperience/2025/11/24/xbox-full-screen-gaming-experience-now-available-for-windows-11-handhelds-and-in-preview-for-pcs/
- Notebookcheck, Xbox mode live, sleep/resume caveats: https://www.notebookcheck.net/Xbox-mode-is-now-live-on-Windows-11.1288165.0.html
- Engadget, Xbox mode rollout: https://www.engadget.com/2161816/microsoft-xbox-mode-windows-11-rollout/
- Playnite README (Playnite 11 rewrite status): https://raw.githubusercontent.com/JosefNemec/Playnite/master/README.md
- Playnite 11 developer docs (alpha): https://api.playnite.link/docs/wpfdevel11/manual/intro.html
- Microsoft Q&A, Xbox controller Bluetooth wake: https://learn.microsoft.com/en-us/answers/questions/4030464/allow-xbox-controller-integrated-bluetooth-to-wake
- Microsoft KB 266283, Bluetooth wake limitations: https://support.microsoft.com/kb/266283
- Steam Community, Xbox controller wake via adapter: https://steamcommunity.com/discussions/forum/1/458604254438911646
- IsThereAnyDeal API docs: https://docs.isthereanydeal.com/
- Heroic Games Launcher README: https://raw.githubusercontent.com/Heroic-Games-Launcher/HeroicGamesLauncher/main/README.md
- Legendary moves to a new organisation (Apr 2026): https://www.gamingonlinux.com/2026/04/legendary-the-free-and-open-source-epic-games-launcher-has-moved-to-a-new-organisation/
