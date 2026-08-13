# ios-platform

Die gemeinsame Umgebung der bickelmeister-iOS-Apps: `diaro-ios`, `portio-ios`,
`fincheck-ios`.

Hier liegt alles, was in allen Apps gleich sein soll — CI, Release, Lint-Regeln,
Agentenregeln. Die App-Repos enthalten davon so wenig wie möglich, damit eine
Änderung an einer Stelle überall wirkt statt dreimal nachgezogen werden zu müssen.

> Dieses Repo ist **public**. Nicht aus Prinzip, sondern aus Notwendigkeit:
> wiederverwendbare Workflows aus einem privaten Repo sind unter einem
> User-Account nicht repo-übergreifend aufrufbar. Es enthält keine Secrets.

## Aufbau

```
.github/workflows/     Wiederverwendbare Workflows (workflow_call)
  ios-ci.yml           SwiftLint (ubuntu) → Build & Test (macOS)
  ios-nightly.yml      Täglicher Check: main seit letztem Upload geändert? → baut ios-release.yml
  ios-release.yml      Archive, Signieren, TestFlight-Upload (reiner Build-Baustein)
  ios-trunk-tag.yml    trunkVersion-Tag nach grünem CI auf main
shared/                Dateien, die per Sync in die App-Repos wandern
  .swiftlint.yml
  .editorconfig
  Makefile.shared      Der gemeinsame Teil des Makefiles
  AGENTS.core.md       Der gemeinsame Teil von AGENTS.md
  PULL_REQUEST_TEMPLATE.md
scripts/sync.sh        Verteilt shared/ und öffnet je einen PR
```

## Zwei Verteilungswege

**Workflows werden nicht verteilt.** Die App-Repos rufen sie auf:

```yaml
# <app-repo>/.github/workflows/ci.yml
name: CI
on:
  pull_request:
    paths-ignore: ["**/*.md", "LICENSE"]
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    uses: bickelmeister/ios-platform/.github/workflows/ios-ci.yml@v1
    with:
      project: diaro-ios.xcodeproj
      scheme: diaro-ios
      lint-paths: diaro-ios diaro-iosTests
```

Eine Änderung hier plus `v1`-Tag verschieben wirkt beim nächsten CI-Lauf in allen
Repos — ohne dass ein App-Repo angefasst wird.

> **CI läuft nur auf Pull Requests, nicht zusätzlich auf Pushes nach `main`.**
> Die App-Repos sind privat: 2.000 Actions-Minuten im Monat, und macOS zählt
> 10-fach — also rund 200 echte macOS-Minuten für alle Apps zusammen. Ein Lauf
> auf `main` würde denselben Baum ein zweites Mal prüfen und das Kontingent
> halbieren. Der Preis: bei Squash-Merge wird der Commit auf `main` selbst nie
> gebaut, nur der PR-Stand davor. Wenn das eng wird, sind die Auswege ein
> self-hosted Runner auf dem eigenen Mac oder ein Organization-Account.

Der Nightly-Release-Lauf braucht Schreibrechte, um seine Tags zu setzen (siehe
"Stolperstein" unten):

```yaml
# <app-repo>/.github/workflows/nightly.yml
name: Nightly
on:
  schedule:
    - cron: '0 3 * * *'
  workflow_dispatch:
permissions:
  contents: write
jobs:
  nightly:
    uses: bickelmeister/ios-platform/.github/workflows/ios-nightly.yml@v1
    with:
      project: diaro-ios.xcodeproj
      scheme: diaro-ios
    secrets: inherit
```

Details zum Tag-Schema, Ablauf und Troubleshooting: [docs/release.md](docs/release.md).

**Dateien werden verteilt**, weil man `.swiftlint.yml` oder ein Makefile nicht
aufrufen kann:

```sh
scripts/sync.sh              # Probelauf: zeigt nur, was sich ändern würde
scripts/sync.sh --apply      # Branch anlegen, pushen, PR öffnen
scripts/sync.sh --apply diaro-ios
```

`Makefile` und `AGENTS.md` gehören nur teilweise der Plattform. Der geteilte Teil
steht zwischen Markern, alles außerhalb bleibt repo-eigen:

```markdown
<!-- SYNC:START ios-platform -->
… wird von sync.sh ersetzt, hier nichts von Hand ändern …
<!-- SYNC:END ios-platform -->
```

Im Makefile lauten die Marker `# SYNC:START ios-platform` / `# SYNC:END ios-platform`.
Fehlen die Marker, lässt `sync.sh` die Datei in Ruhe.

## Versionierung

Die App-Repos zeigen auf `@v1`. Nach einer Änderung:

```sh
git tag -f v1 && git push --force origin refs/tags/v1
```

Bei einer Änderung, die die App-Repos anpassen müssen (neuer Pflicht-Input, neues
Secret), stattdessen `v2` anlegen und die Repos einzeln umstellen — ein
verschobenes `v1` darf nie einen roten CI-Lauf verursachen.

## Ein neues iOS-Repo anschließen

1. `.swiftlint.yml`, `.editorconfig`, `.github/PULL_REQUEST_TEMPLATE.md` aus
   `shared/` kopieren.
2. `Makefile` anlegen: Kopf mit `PROJECT`, `SCHEME`, `BUNDLE_ID`, `SOURCES`,
   `SIM`, darunter `Makefile.shared` zwischen den SYNC-Markern.
3. `AGENTS.md` anlegen: repo-spezifischer Teil plus `AGENTS.core.md` zwischen den
   SYNC-Markern. `CLAUDE.md` als Symlink darauf:
   `ln -s AGENTS.md CLAUDE.md && git add CLAUDE.md`
4. Caller-Workflows für `ios-ci.yml`, `ios-trunk-tag.yml`, `ios-nightly.yml` anlegen.
5. `fastlane/` mit `Appfile`, `Fastfile`, `Matchfile` anlegen; `match appstore`
   für die Bundle-ID laufen lassen.
6. GitHub Environment `release` anlegen (Settings → Environments), darin die
   fünf Secrets setzen: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `MATCH_PASSWORD`, `MATCH_GIT_TOKEN`. Optional Protection Rules (z. B.
   Required Reviewers) für den Upload-Job aktivieren.
7. Branch Protection auf `main` (nur bei public Repos kostenlos).
8. Ersten Marketingversion-Tag setzen: `make bump-version VERSION=1.0.0`.
9. Repo-Name in `scripts/sync.sh` in `REPOS` eintragen.

> **Stolperstein:** Die Caller für `ios-nightly.yml` und `ios-trunk-tag.yml`
> brauchen ein eigenes `permissions: contents: write`. Ein aufgerufener Workflow
> kann nie *mehr* Rechte bekommen als sein Aufrufer — das `permissions` im
> zentralen Workflow allein reicht also nicht, wenn die Repo-Voreinstellung auf
> read-only steht. Nachsehen mit:
>
> ```sh
> gh api /repos/bickelmeister/<repo>/actions/permissions/workflow
> ```

Die Signing- und Secret-Schritte stehen ausführlich in [docs/setup.md](docs/setup.md).

Als Vorlage dient `diaro-ios`: dort ist der Weg vollständig gegangen — drei
Caller-Workflows, match-Signierung, Release bis TestFlight.

## Secrets

Liegen im GitHub Environment `release` des jeweiligen App-Repos, nicht als
einfache Repo-Secrets — nur so lassen sich Protection Rules (z. B. Required
Reviewers) auf den Upload-Job anwenden.

| Name | Woher |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → Key ID |
| `ASC_ISSUER_ID` | ebenda, Issuer ID (für alle Apps gleich) |
| `ASC_KEY_P8` | `base64 -i AuthKey_XXXX.p8` |
| `MATCH_PASSWORD` | Passphrase, mit der `ios-certificates` verschlüsselt ist |
| `MATCH_GIT_TOKEN` | base64 von `bickelmeister:<PAT>` — nicht der rohe Token |

Zertifikate und Profile liegen in `bickelmeister/ios-certificates` (private),
verwaltet mit `fastlane match`. Kein Zertifikat wird je in ein App-Repo gelegt.
