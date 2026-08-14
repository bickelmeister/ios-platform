# Release-Prozess: Nightly-TestFlight-Uploads

Releases laufen nicht mehr manuell über ein GitHub Release, sondern
automatisch: ein täglicher Nightly-Workflow prüft, ob sich `main` seit dem
letzten erfolgreichen TestFlight-Upload geändert hat, und baut nur dann.

## Die drei Git-Tags

Pro App-Repo gibt es drei Tag-Namensräume, die nichts miteinander zu tun haben
und getrennt voneinander leben:

| Tag | Wer setzt ihn | Wofür |
| --- | --- | --- |
| `vX.Y.Z` | Du, manuell (`make bump-version`) | Marketingversion (`CFBundleShortVersionString`) |
| `build/N` | `ios-nightly.yml`, automatisch | Buildnummer-Zähler (`CFBundleVersion`), rein numerisch |
| `testflight-last` | `ios-nightly.yml`, nur nach Erfolg | Merkt sich, welcher Commit zuletzt hochgeladen wurde |

Keiner dieser Tags erzeugt ein GitHub Release oder löst selbst einen Workflow
aus. Marketingversion und Buildnummer werden nie in `project.pbxproj`
geschrieben — sie gehen nur als Build-Parameter (`MARKETING_VERSION`,
`CURRENT_PROJECT_VERSION`) in den Archive-Schritt. `main` bleibt dadurch frei
von automatisierten Commits außerhalb von Pull Requests.

## Ablauf eines Nightly-Laufs

`ios-nightly.yml` (aufgerufen vom App-Repo, siehe unten) macht bei jedem Lauf:

1. **Prüfen**: `main`-HEAD mit dem Commit vergleichen, auf den
   `testflight-last` zeigt. Identisch → nichts zu tun, Lauf endet grün ohne
   Build.
2. **Buildnummer reservieren**: höchste vorhandene `build/N` suchen, `N+1` als
   Tag auf `HEAD` pushen. Schlägt der Push fehl (ein paralleler Lauf war
   schneller), wird die nächste Nummer versucht — bis zu 20 Mal. Das ist
   race-frei, weil Git das Erstellen eines bereits existierenden Tags
   serverseitig ablehnt.
3. **Marketingversion lesen**: `git describe --tags --match 'v*' --abbrev=0`
   ab `main`-HEAD — der nächstgelegene erreichbare `vX.Y.Z`-Tag. Bleibt über
   beliebig viele Nightly-Läufe stabil, bis du den nächsten Tag setzt.
4. **Bauen**: `ios-release.yml` mit Marketingversion und Buildnummer als
   Inputs aufrufen — archiviert, signiert über `match`, lädt zu TestFlight
   hoch.
5. **Erfolg markieren**: erst wenn der Upload durchgelaufen ist, wird
   `testflight-last` per Force-Push auf den gebauten Commit verschoben. Bricht
   der Upload ab, bleibt `testflight-last` auf dem alten Stand — der nächste
   Nightly-Lauf versucht denselben Commit erneut, mit einer neuen
   Buildnummer (die alte bleibt als verbrauchte Reservierung stehen und wird
   nie wiederverwendet).

## Caller-Workflow im App-Repo

```yaml
# .github/workflows/nightly.yml
name: Nightly

on:
  # Vorerst nur manuell ausgelöst (Actions → Nightly → Run workflow), um
  # macOS-Minuten im Free Tier zu sparen (macOS zählt 10-fach). Sobald das
  # Kontingent wieder Luft hat, `schedule:` ergänzen:
  #
  #   schedule:
  #     - cron: '0 3 * * *'
  workflow_dispatch:

jobs:
  nightly:
    uses: bickelmeister/ios-platform/.github/workflows/ios-nightly.yml@v2
    with:
      project: diaro-ios.xcodeproj
      scheme: diaro-ios
    secrets: inherit
```

Ohne `schedule` muss der Build manuell ausgelöst werden — der `check`-Job
(Vergleich mit `testflight-last`) verhindert aber wie beim geplanten Lauf
unnötige Builds, falls sich seit dem letzten Upload nichts geändert hat.

## Marketingversion hochziehen

```sh
make bump-version VERSION=1.5.0
```

Setzt `v1.5.0` auf den aktuellen `main`-Stand und pusht den Tag. Der nächste
Nightly-Lauf baut damit automatisch unter der neuen Version — ohne dass extra
etwas getriggert werden muss. Bis dahin laufen weitere Nightly-Builds unter der
bisherigen Marketingversion mit steigenden Buildnummern weiter.

## Troubleshooting

| Situation | Ursache / Vorgehen |
| --- | --- |
| `Kein vX.Y.Z-Tag in der Historie gefunden` | Neues Repo ohne ersten Tag. Einmalig `make bump-version VERSION=1.0.0` ausführen. |
| `Konnte nach 20 Versuchen keine Build-Nummer reservieren` | Sehr unwahrscheinlich außer bei kaputtem Netzwerk/Berechtigungen; `contents: write` des Callers prüfen (siehe README, Abschnitt "Stolperstein"). |
| Nightly baut trotz unveränderter `main` erneut | `testflight-last` wurde von Hand verschoben oder gelöscht — Historie mit `git log testflight-last` prüfen. |
| Build in ASC schon vorhanden (`entity … already used`) | Kann durch die Tag-Reservierung eigentlich nicht mehr passieren; falls doch, war die App vorher schon manuell mit derselben Nummer bespielt — nächster Nightly-Lauf zählt automatisch weiter. |
| Nightly soll sofort laufen, nicht erst nachts | Im App-Repo unter **Actions → Nightly → Run workflow** manuell auslösen (workflow_dispatch). |

## App Store Connect bleibt Handarbeit

Der Nightly-Workflow lädt nur zu TestFlight hoch (`skip_submission: true`).
Build einer Version zuweisen, Screenshots und "Submit for Review" passieren
weiterhin manuell in App Store Connect.

Die deutschen Release Notes sind die Ausnahme: `make release-notes` lädt den
Text aus `fastlane/metadata/de-DE/release_notes.txt` per Fastlane `deliver`
hoch (`skip_screenshots`, `skip_binary_upload`, `skip_app_version_update`,
`submit_for_review: false`) — nur der Text, kein Einreichen.

## Release Notes ohne lokale Secrets hochladen

`make release-notes` braucht lokal die drei `APP_STORE_CONNECT_API_KEY_*`
Umgebungsvariablen mit demselben API-Key, der auch für den Nightly-Upload
verwendet wird — die liegen nicht in jedem Laptop-Environment. Alternative:
`ios-release-notes.yml` macht denselben `fastlane release_notes`-Aufruf als
manuell auslösbaren Workflow, der die schon im Environment `release` liegenden
Secrets wiederverwendet. Kein Xcode-Archiv, läuft auf ubuntu.

```yaml
# .github/workflows/release-notes.yml
name: Release Notes

on:
  workflow_dispatch:

jobs:
  release-notes:
    uses: bickelmeister/ios-platform/.github/workflows/ios-release-notes.yml@v2
    secrets: inherit
```

Auslösen über **Actions → Release Notes → Run workflow** im App-Repo.
