# Changelog — Farul (macOS)

## v0.2.0 (2026-11-14) — Candidat local

### Added
- Eșantionarea se oprește la somn și repornește curat la trezire.
- Diagnostic: ID de sesiune, versiune în log, export ZIP redactat, folderul de loguri din Setări.
- Dezinstalare completă din Setări, cu lista exactă a fișierelor.
- Actualizare verificată: sumă de control, semnătura dezvoltatorului, versiune mai nouă; copie de siguranță și revenire automată.

### Fixed
- Presiunea de memorie urmează nucleul, nu o euristică (arăta „critic” când sistemul raporta „avertisment”).
- Textele de actualizare și dezinstalare sunt în română, engleză și spaniolă.

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
