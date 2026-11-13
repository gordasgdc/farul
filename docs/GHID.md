# Farul — ghid / guide / guía (0.2.0)

## RO
**Ce face:** arată în bara de meniu procesorul, memoria, rețeaua, discurile, bateria și procesele active. Totul rămâne pe calculatorul tău.
**Limba:** Setări → General → Limbă (Urmează sistemul / Română / English / Español). Implicit urmează sistemul; dacă limba lui nu e acoperită, folosește româna. Alegerea se păstrează după repornire.
**Diagnostic:** Setări → Diagnostic: *Deschide folderul de loguri* (`/Users/<tu>/Library/Logs/Farul.log`), *Copiază ID-ul sesiunii*, *Exportă diagnosticul…* (ZIP local, redactat; nu se trimite nicăieri), *Jurnal detaliat (o oră)*.
**Actualizare:** meniul → *Verifică actualizări…*. Farul descarcă pachetul, verifică suma de control, semnătura dezvoltatorului și versiunea, apoi cere parola de administrator. Aplicația veche se salvează în `/Users/<tu>/Library/Application Support/Farul/Rollback/` și revine automat dacă instalarea eșuează.
**Dezinstalare:** Setări → Dezinstalare → *Dezinstalează complet aplicația…*. Șterge: `Library/Application Support/Farul`, `Library/Preferences/dev.gordas.Farul.plist`, `Library/Caches/dev.gordas.Farul`, `Library/Logs/Farul.log` și `.1`, `Library/Saved Application State/dev.gordas.Farul.savedState`, `Library/HTTPStorages/dev.gordas.Farul*`, `Library/WebKit/dev.gordas.Farul`, și mută aplicația la Coș. Lista exactă apare în confirmare.

## EN
**What it does:** shows CPU, memory, network, disks, battery and active processes in the menu bar. Everything stays on your computer.
**Language:** Settings → General → Language (Follow system / Română / English / Español). By default it follows the system; if the system language is not covered it uses Romanian. Your choice persists across restarts.
**Diagnostics:** Settings → Diagnostics: *Open logs folder* (`~/Library/Logs/Farul.log`), *Copy session ID*, *Export diagnostics…* (local, redacted ZIP; never uploaded), *Detailed log (one hour)*.
**Updating:** menu → *Check for updates…*. Farul downloads the package, verifies its checksum, the developer's signature and the version, then asks for the administrator password. The previous app is saved in `~/Library/Application Support/Farul/Rollback/` and restored automatically if the install fails.
**Uninstall:** Settings → Uninstall → *Uninstall the app completely…*. The exact list of files is shown in the confirmation (same paths as above) and the app moves to the Trash.

## ES
**Qué hace:** muestra en la barra de menús CPU, memoria, red, discos, batería y procesos activos. Todo permanece en tu ordenador.
**Idioma:** Ajustes → General → Idioma (Seguir el sistema / Română / English / Español). Por defecto sigue al sistema; si su idioma no está cubierto, usa rumano. Tu elección se conserva al reiniciar.
**Diagnóstico:** Ajustes → Diagnóstico: *Abrir la carpeta de registros* (`~/Library/Logs/Farul.log`), *Copiar el ID de sesión*, *Exportar diagnóstico…* (ZIP local y redactado; no se envía), *Registro detallado (una hora)*.
**Actualización:** menú → *Buscar actualizaciones…*. Farul descarga el paquete, verifica la suma de control, la firma del desarrollador y la versión, y luego pide la contraseña de administrador. La app anterior se guarda en `~/Library/Application Support/Farul/Rollback/` y se restaura sola si la instalación falla.
**Desinstalación:** Ajustes → Desinstalación → *Desinstalar la aplicación por completo…*. La lista exacta de archivos aparece en la confirmación y la app pasa a la Papelera.
