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
  ios-release.yml      Version setzen, Archive, Signieren, TestFlight
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
  push:
    branches: [main]
    paths-ignore: ["**/*.md", "LICENSE"]
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
4. Caller-Workflows für `ios-ci.yml`, `ios-trunk-tag.yml`, `ios-release.yml` anlegen.
5. `fastlane/` mit `Appfile`, `Fastfile`, `Matchfile` anlegen; `match appstore`
   für die Bundle-ID laufen lassen.
6. Repo-Secrets setzen: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `MATCH_PASSWORD`, `MATCH_GIT_TOKEN`.
7. Branch Protection auf `main`: CI muss grün sein.
8. Repo-Name in `scripts/sync.sh` in `REPOS` eintragen.

Für neue Apps gibt es dafür `bickelmeister/ios-app-template` — dort ist das alles
schon fertig.

## Secrets

| Name | Woher |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → Key ID |
| `ASC_ISSUER_ID` | ebenda, Issuer ID (für alle Apps gleich) |
| `ASC_KEY_P8` | `base64 -i AuthKey_XXXX.p8` |
| `MATCH_PASSWORD` | Passphrase, mit der `ios-certificates` verschlüsselt ist |
| `MATCH_GIT_TOKEN` | PAT mit Lesezugriff auf `bickelmeister/ios-certificates` |

Zertifikate und Profile liegen in `bickelmeister/ios-certificates` (private),
verwaltet mit `fastlane match`. Kein Zertifikat wird je in ein App-Repo gelegt.
