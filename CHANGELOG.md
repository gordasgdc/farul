# Changelog — Farul (macOS)

## v0.1.1 (2026-09-19) — Mutare în Aplicații fiabilă

### Fixed
- **Mutarea automată în folderul Aplicații** putea cere mutarea din nou la
  fiecare pornire, iar la a doua confirmare ducea aplicația instalată la Coș.
  Se întâmpla cu aplicația descărcată din browser și dezarhivată, pe care
  macOS o rula dintr-o copie izolată. Acum copia din Aplicații pornește
  normal, iar o instalare deja afectată se repară singură la prima pornire.
- Dacă în Aplicații există deja o copie a administratorului, mutarea cere
  parola de administrator în loc să eșueze.

### Added
- Jurnal de diagnostic local: `~/Library/Logs/Farul.log`; `scripts/logs.sh`
  îl afișează împreună cu unified log-ul.

## v0.1.0 (2026-09-15) — Prima versiune

- Monitor de sistem și rețea în bara de meniu: procesor, memorie, rețea,
  discuri, baterie și procese active; interfață în română, engleză și spaniolă.
