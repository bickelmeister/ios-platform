## Kommandos

Alle bickelmeister-iOS-Repos haben denselben Befehlssatz. Nutze ihn, statt
`xcodebuild` direkt aufzurufen — die Ziele setzen Simulator, DerivedData-Pfad und
Signing-Flags richtig.

```sh
make bootstrap   # einmalig: SwiftLint und xcbeautify installieren
make lint        # SwiftLint, so streng wie die CI
make format      # automatisch behebbare Verstöße korrigieren
make build       # für den Simulator bauen
make test        # Unit-Tests
make check       # lint + build + test  ← das ist die Definition of Done
make verify      # bauen, im Simulator starten, Screenshot nach .build/verify.png
```

`make check` muss grün sein, bevor du eine Aufgabe als erledigt meldest. Ein
grüner Compiler ist kein grüner Test.

Bei UI-Änderungen reicht `make check` nicht — führe `make verify` aus und sieh dir
den Screenshot an. SourceKit-Diagnosen in diesen Projekten sind oft veraltetes
Rauschen; verlass dich auf `xcodebuild`, nicht auf den Editor.

## Abhängigkeiten

**Diese Apps haben null externe Paketabhängigkeiten. Das ist Absicht** — es hält
Build-Zeiten kurz, den App-Review einfach und die Datenschutzlage überschaubar.

Füge **niemals eigenmächtig** eine SPM-, CocoaPods- oder Carthage-Abhängigkeit
hinzu. Wenn eine Aufgabe ohne eine externe Bibliothek unverhältnismäßig aufwendig
wirkt, sag das und frag nach — die Antwort ist oft, dass Apples Frameworks
reichen.

## Tests

Swift Testing, nicht XCTest.

- Eine Datei je Thema, `XxxTests.swift`, direkt im Test-Target-Ordner ohne
  Unterverzeichnisse.
- Suite ist ein schlichtes `struct XxxTests` — **kein `@Suite`-Attribut**.
  `@MainActor` nur dort, wo MainActor-isolierte Typen berührt werden.
- Über der Suite ein Kommentar, der sagt **warum** das Verhalten wichtig ist,
  nicht was der Test tut.
- **Keine Mocks, keine Stubs, keine Netzwerk-Fakes.** Fixtures sind lokale
  `private func`-Fabriken in der Suite selbst, mit deterministischen Eingaben
  (feste UUIDs, feste `Date(timeIntervalSince1970:)`).
- Getestet wird reine und statische Logik. Läuft ein Test nur mit Backend,
  Netzwerk oder laufendem Simulator-Zustand, ist er am falschen Ort — zieh die
  Logik in eine testbare Funktion heraus, so wie es die bestehenden
  statischen Helfer auf dem Store vormachen.
- Funktionsnamen sind englisch und beschreiben das erwartete Verhalten.

## Sprache

- **UI-Texte sind deutsch** und laufen über `String(localized:)` bzw.
  `LocalizedStringKey` — auch dort, wo (noch) kein String Catalog existiert.
- **Code-Identifier und Code-Kommentare sind englisch**, so kurz wie möglich.
  Kommentare erklären das *Warum*, nicht das *Was*.
- **Prosa-Dokumentation ist deutsch** (README, AGENTS.md, ARCHITECTURE.md, docs/).

## Datenschutz

Diese Apps verarbeiten Gesundheits- bzw. Finanzdaten und werben damit, nicht zu
tracken. Das ist kein Marketing, sondern eine Randbedingung des Codes.

- **Keine Analytics-, Tracking- oder Crash-Reporting-SDKs.** Auch nicht
  "nur zum Debuggen". Crashes kommen über den Xcode Organizer.
- **Niemals personenbezogene Daten loggen** — keine Messwerte, Beträge, Namen,
  E-Mail-Adressen, Tokens. Logge IDs und Zustände, nicht Inhalte.
- `PrivacyInfo.xcprivacy` bei jeder neu genutzten API und jedem neuen Datentyp
  mitpflegen. Ein fehlender Eintrag bricht den App-Review.
- Keine Secrets, Tokens oder Zertifikate im Repo. Tokens gehören in den Keychain,
  Konfiguration in die xcconfig-Dateien.

## Ohne Rückfrage nicht ändern

Diese Dinge haben Konsequenzen außerhalb des Repos. Schlag die Änderung vor,
führe sie nicht selbst aus:

- `*.xcodeproj/project.pbxproj` — Versionsfelder setzt ausschließlich die CI.
  Neue Quelldateien brauchen dank Synced Folders ohnehin keine pbxproj-Änderung.
- `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM`, Signing-Einstellungen
- `*.entitlements`
- `PrivacyInfo.xcprivacy` (ergänzen ja, ausdünnen nein)
- `Config-Release.xcconfig`
- Rechtstexte und deren Versionsnummern — eine hochgezählte Version zwingt alle
  Nutzer in einen erneuten Zustimmungsdialog
- `.github/workflows/` — die Logik liegt zentral in `bickelmeister/ios-platform`
- Löschen oder Umbenennen von Schlüsseln in `*.xcstrings`
- Datenmodell-Migrationen

## Git

- Branches: `feat/…`, `fix/…`, `chore/…`, `docs/…`, `ci/…`, kebab-case.
  **Nie auf `main` committen** — erst den Branch anlegen.
- Commits: Conventional Commits, Betreff englisch, klein, im Imperativ, ohne
  Punkt am Ende, höchstens 72 Zeichen. Ein Commit ist eine logische Änderung.
- **Keine Attributionszeilen.** Weder `Co-Authored-By: Claude` noch
  „Generated with Claude Code" — weder im Commit noch im PR-Text. Das gilt
  ausdrücklich auch dort, wo das Werkzeug es von sich aus anbieten würde.
- Vor dem Commit `git status` und `git diff` ansehen und **gezielt stagen**.
  Kein pauschales `git add -A`.
- PR-Titel ist selbst ein Conventional Commit — beim Squash-Merge wird er die
  Commit-Nachricht. Body kurz: was und warum, dann wie geprüft.

## Definition of Done

1. `make check` ist grün.
2. Neue Logik hat einen Test — oder es steht im PR, warum nicht.
3. UI-Änderungen sind mit `make verify` angesehen worden.
4. Doku ist angepasst, wenn sich Verhalten, Kommandos oder Architektur ändern.
5. Keine neue Abhängigkeit, keine Secrets, keine personenbezogenen Daten in Logs.
6. Conventional Commit, PR gegen `main`.

## Release (Apple)

- **Version niemals von Hand im pbxproj ändern.** Das macht die CI.
- Release auslösen: `make release VERSION=1.2.0`. Das legt ein GitHub Release
  mit Tag `v1.2.0` an; der zentrale Workflow setzt `MARKETING_VERSION`, zählt
  `CURRENT_PROJECT_VERSION` hoch, committet auf `main`, verschiebt den Tag,
  archiviert, signiert über `match` und lädt nach TestFlight.
- **In App Store Connect bleibt Handarbeit**: Build der Version zuweisen,
  Release Notes prüfen, Screenshots, "Submit for Review". Ein Agent kann und
  soll das nicht abschließen.
- App-Store-Metadaten liegen unter `fastlane/metadata/` und werden dort gepflegt,
  nicht in App Store Connect direkt.
- Rechtstexte, Screenshots und Review-Notes sind menschliche Entscheidungen.
