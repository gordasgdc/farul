# Farul — reguli de arhitectură (macOS)

> **[SYSTEM DIRECTIVE FOR CLAUDE: DO NOT DELETE OR OVERWRITE EXISTING RULES. ONLY APPEND NEW RULES.]**
> Acest fișier e un jurnal viu, nu un document care se rescrie.

## [PARTEA 1: REGULI GLOBALE ECOSISTEM GDC] — mutată în `~/Developer/CLAUDE.md`

> Din 2026-09-18, regulile globale stau într-un singur fișier,
> `~/Developer/CLAUDE.md`, citit automat de Claude Code în orice proiect din
> `~/Developer/`. Nu se mai copiază aici. Ce era specific acestui repo în fosta
> Partea 1 (statusuri, excepții) e la finalul fișierului.

## [PARTEA 2: SPECIFICAȚII TEHNICE PROIECT]

### Identitate

- **Nume produs**: Farul — monitor de sistem și rețea pentru macOS.
- **Bundle ID**: `dev.gordas.Farul`.
- **Slug site**: `gordas.dev/farul`.
- **Repo**: `gordasgdc/farul`.
- **Autor unic**: Cristi Gordaș / GDC. Fără nicio mențiune de AI/Claude în
  cod, comentarii, commit-uri, documentație sau pagini web (Regula 32).
- **Numele**: „Farul” — construcția care veghează și semnalează. Metafora
  ține toată aplicația: un far nu conduce nava, doar arată clar unde ești.

### Ce e, ce nu e

Farul arată, în timp real: **procesor, memorie, rețea, discuri, baterie și
procesele active** — setul de funcționalități consacrat de monitoarele de
sistem din bara de meniu.

**Precizare de proveniență, scrisă ca să nu se rescrie istoria mai târziu:**
iStat Menus (Bjango) este un produs **comercial, cu sursă închisă**. Nu
există un „proiect eSTAT/istat pe GitHub” din care să se porteze module —
ce există public sunt utilitare distincte (`iStats`, gem Ruby, MIT) și
monitoare open-source neînrudite. Prin urmare Farul **nu portează cod de
nicăieri**: reimplementează, de la zero și în Swift, aceleași categorii de
măsurători, folosind API-urile publice macOS (`host_statistics64`,
`getifaddrs`, `IOPowerSources`, `libproc`, `URLResourceValues`). Asta e și
singura variantă legală, și singura care poate respecta Regula 30 („zero cod
impur sau nelalocul lui”).

### Localizare — trilingv integral, nu parțial

RO / EN / ES peste TOATĂ interfața, meniurile și documentația. Limba
implicită urmează sistemul, cu română ca plasă de siguranță, și poate fi
forțată explicit din Setări (același tipar ca selectorul de temă din Regula
18: unii vor engleză pe un macOS în română).

Toate textele trec prin `Localization.swift` — `L.t(.cheie)`. Un literal
scris direct într-un `Text(...)` e un bug, nu o scurtătură: nu poate fi
tradus și nu poate fi găsit.

### Design

Glassmorphic / translucent, nativ macOS: `.ultraThinMaterial`,
`NSVisualEffectView` pentru materiale de fereastră, colțuri rotunjite
consecvente, micro-animații discrete. Paleta respectă Regula 37 — zero
culori literale pe controale, doar culori semantice sau tokeni.

### Actualizări

Sistem hibrid, prin `gordas.dev/farul/update.json`, pe modelul deja
implementat în GDC Firewall: manifestul poartă `app_version` (și `version`
ca sinonim păstrat pentru totdeauna, Regula 35), iar `UpdateChecker` +
`SelfUpdater` rămân cele standard — descărcare și instalare asistată,
niciodată un browser deschis (Regula 20).

### Arhitectură

```
macOS/Farul/Sources/Farul/
  FarulApp.swift          — ciclul de viață, MenuBarExtra, ferestre
  Localization.swift      — RO/EN/ES, selector persistat
  AppTheme.swift          — Sistem/Light/Dark (Regula 18)
  AppMover.swift          — mutare în /Applications (Regula 18)
  UpdateChecker.swift     — update.json (Regulile 13, 20, 35)
  SelfUpdater.swift       — descărcare + instalare asistată
  Metrics/                — un colector per categorie, fără UI în ele
    SystemSampler.swift   — ceasul comun: un timer, nu șase
    CPUMonitor.swift      — host_processor_info, per nucleu + total
    MemoryMonitor.swift   — host_statistics64 + vm.swapusage
    NetworkMonitor.swift  — getifaddrs, delta per interfață
    DiskMonitor.swift     — volume montate, capacitate și spațiu liber
    BatteryMonitor.swift  — IOPowerSources + AppleSmartBattery
    ProcessMonitor.swift  — libproc, top procese după CPU și memorie
  UI/                     — carduri, grafice, ferestre
```

**Un singur ceas.** Toate colectoarele sunt eșantionate de `SystemSampler`,
la un interval unic, configurabil. Șase timere independente ar produce șase
treziri diferite ale procesorului — exact opusul scopului unei aplicații
care se laudă că e ușoară.

### Jurnal

- **2026-09-19 — v0.1.1.** AppMover portat din GDC Firewall (Regula 40):
  judecă locația după original, copia din `/Applications` primește carantina
  fără bitul 0x0080, instalare izolată = reparare pe loc. `DiagnosticLog`
  (`~/Library/Logs/Farul.log`) + `scripts/logs.sh` (Regula 39); textele
  alertelor în `L.t(.appMover…)`. Test live (macOS 26.6.2, SIP dezactivat,
  build notarizat semnat cu modulul `codesigning/` din GDC Vault, zip cu
  carantină `0083`, Archive Utility, pornit din `~/Downloads`): mutare fără
  admin, `0043`, original la Coș, repornit neizolat; reparare pe loc
  (`00c3` → `0043`, fără buclă). Lipsesc încă, găsite la acest test:
  `scripts/build_app.sh` (menționat în `LocalizationAudit`), modulul
  `codesigning/` (folder gol), dezinstalatorul (Regula 6), `docs/update.json`
  — iar sursa aplicației (`macOS/`, `scripts/`) nu e încă în git.
- **2026-09-15 — v0.1.0.** Proiect nou. Schelet, localizare trilingvă,
  colectoare de metrici, interfață glassmorphic, pictogramă din sursă
  vectorială, scripturi de build.

### Completări specifice acestui repo, mutate din fosta Partea 1 (2026-09-18)

Păstrate verbatim. Regula generală la care se referă fiecare e în
`~/Developer/CLAUDE.md`.

**Regula 34:**

  build-windows.yml` + `codesigning/`, 2026-09-06) — acest repo
  (MediaFlow Monitor) e portul 1:1, adaptat la propriile căi
  (`Publish\Windows\win-<arch>\MediaFlowMonitor.exe`,
  `dist\MediaFlowMonitorSetup-<arch>-<versiune>.exe`), aplicat la
  aceeași atingere (2026-09-06) — vezi `codesigning/README-windows.md`
  din acest repo pentru pașii exacți ai lui Cristi.

### Handoff — fișierul de stare (Regula 50, `~/Developer/CLAUDE.md`)

- Fișierul de stare al acestui proiect: `PROJECT_STATE.md` (rădăcina repo-ului). La orice sesiune nouă se citește
  ÎNTÂI el, apoi doar fragmentele strict necesare; se actualizează la milestone-uri și obligatoriu la final.
  Dacă lipsește, se creează la prima sesiune care atinge proiectul. Repo PUBLIC: fișierul e intern, listat în `.gitignore` (doar local, Regula 29).
- Restructurarea/ștergerea lui și orice modificare a acestui `CLAUDE.md`: doar cu diff-ul arătat și acordul lui Cristi.
