# Einrichtung: Signing und Secrets

Einmalig für alle Apps zusammen: der App-Store-Connect-Key und das
`match`-Repository. Danach je App: `match` einmal laufen lassen und fünf Secrets
setzen.

Rechne mit gut einer Stunde für den gemeinsamen Teil und zehn Minuten je App.

---

## Voraussetzung: Die App muss in App Store Connect existieren

`upload_to_testflight` lädt in einen bestehenden App-Datensatz. Gibt es ihn
nicht, bricht der Release-Lauf mit einer wenig hilfreichen Meldung ab.

Prüfen unter [App Store Connect → Apps](https://appstoreconnect.apple.com/apps).
Fehlt die App, dort zuerst anlegen (`+` → Neue App) mit exakt der Bundle-ID aus
`fastlane/Appfile`. Die Bundle-ID muss vorher im
[Developer Portal](https://developer.apple.com/account/resources/identifiers)
als Identifier registriert sein.

| App | Bundle-ID |
| --- | --- |
| diaro-ios | `studio.startblock.diaro` |
| portio-ios | `studio.startblock.portio` |
| fincheck-ios | `bickelmeister.dev.fincheck-ios` |

---

## Schritt 1 — App-Store-Connect-API-Key

Ein Key für alle drei Apps. Er ersetzt Apple-ID und App-spezifische Passwörter
und ist nicht an die Zwei-Faktor-Authentifizierung gebunden — deshalb
funktioniert er in CI.

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access**
   → Reiter **Integrations** → **App Store Connect API** → **Team Keys**
2. **`+`**, Name z. B. `GitHub Actions`, Access: **App Manager**
   > `App Manager` reicht zum Hochladen von Builds. `Admin` brauchst du nur,
   > wenn `match` neue Zertifikate über die API anlegen soll — beim ersten
   > Durchlauf meldest du dich stattdessen einmal mit der Apple-ID an, dann
   > genügt `App Manager` dauerhaft.
3. **Generate**. Jetzt notieren:
   - **Key ID** (steht in der Zeile, z. B. `2X9ABC3DEF`) → das wird `ASC_KEY_ID`
   - **Issuer ID** (steht oberhalb der Tabelle, eine UUID) → `ASC_ISSUER_ID`
4. **Download API Key** — die `.p8`-Datei lässt sich **nur ein einziges Mal**
   herunterladen. Leg sie sofort in deinen Passwortmanager.
5. Für das Secret brauchst du sie base64-kodiert:

   ```sh
   base64 -i ~/Downloads/AuthKey_2X9ABC3DEF.p8 | pbcopy
   ```

   Das liegt jetzt in der Zwischenablage → das wird `ASC_KEY_P8`.

---

## Schritt 2 — Zertifikats-Repository

`fastlane match` legt Zertifikat und Provisioning Profiles verschlüsselt in ein
Git-Repo. Jede Maschine — dein Mac, der CI-Runner — holt sie von dort. Damit gibt
es genau ein Distributionszertifikat statt eines je Rechner, und in keinem
App-Repo liegt jemals ein Schlüssel.

1. Repo **`bickelmeister/ios-certificates`** auf GitHub anlegen: **private**,
   ohne README, ohne .gitignore, ohne Lizenz. Vollständig leer.

2. Eine Passphrase ausdenken und im Passwortmanager ablegen. Mit ihr wird der
   Inhalt verschlüsselt → das wird `MATCH_PASSWORD`. Sie ist nirgends
   wiederherstellbar; ist sie weg, muss `match` von vorn aufgesetzt werden.

3. Fine-grained Personal Access Token für den Lesezugriff der CI:

   - GitHub → **Settings** → **Developer settings** →
     **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
   - Name: `ios-certificates read`
   - Expiration: 1 Jahr (Kalendereintrag zum Erneuern machen)
   - **Repository access** → *Only select repositories* → `ios-certificates`
   - **Permissions** → Repository permissions → **Contents: Read-only**
   - Generieren, Token kopieren.

4. `match` erwartet den Token **nicht** roh, sondern als base64-kodiertes
   `benutzername:token`. Das ist die Stelle, an der die meisten Setups scheitern:

   ```sh
   echo -n "bickelmeister:github_pat_DEIN_TOKEN" | base64 | pbcopy
   ```

   Das Ergebnis wird `MATCH_GIT_TOKEN`. Wichtig ist `echo -n` — ein
   Zeilenumbruch am Ende macht den Token ungültig.

---

## Schritt 3 — `match` je App einmal lokal laufen lassen

Im App-Repo (Beispiel `diaro-ios`):

```sh
cd ~/Documents/bickelmeister_dev/diaro-ios
bundle install
bundle exec fastlane match appstore
```

Beim ersten Lauf fragt `match`:

- **Passphrase** → die aus Schritt 2. Er bietet an, sie im lokalen Keychain zu
  merken; annehmen.
- **Apple-ID und 2FA-Code** → nur beim allerersten Mal, weil das
  Distributionszertifikat neu angelegt werden muss.

Danach liegen im `ios-certificates`-Repo ein verschlüsseltes Zertifikat und ein
Profil für die Bundle-ID. Für die zweite und dritte App wiederholt sich nur der
Profil-Teil — das Zertifikat wird wiederverwendet.

> **Nicht `match nuke` ausführen**, solange eine App im Store ist. Das widerruft
> Zertifikate teamweit.

Prüfen, dass es geklappt hat:

```sh
bundle exec fastlane match appstore --readonly
```

Läuft das ohne Apple-Login durch, kann die CI es auch.

---

## Schritt 4 — Secrets im App-Repo setzen

Fünf Stück, je Repo dieselben Werte:

```sh
cd ~/Documents/bickelmeister_dev/diaro-ios

gh secret set ASC_KEY_ID        # Key ID aus Schritt 1
gh secret set ASC_ISSUER_ID     # Issuer ID aus Schritt 1
gh secret set ASC_KEY_P8        # base64 der .p8 aus Schritt 1
gh secret set MATCH_PASSWORD    # Passphrase aus Schritt 2
gh secret set MATCH_GIT_TOKEN   # base64 von "bickelmeister:token" aus Schritt 2
```

`gh secret set` fragt den Wert interaktiv ab, er landet also nicht in der
Shell-History. Kontrolle:

```sh
gh secret list
```

Für die anderen Repos dasselbe, oder direkt kopieren:

```sh
for r in portio-ios fincheck-ios; do
  gh secret set ASC_KEY_ID --repo "bickelmeister/$r"
  # …
done
```

---

## Schritt 5 — Erster Release-Lauf

Secrets liegen im GitHub Environment `release`, nicht als Repo-Secrets — dieses
Environment im App-Repo zuerst anlegen (Settings → Environments → New
environment → `release`), dann Schritt 4 dort statt in den Repo-Secrets
ausführen.

Danach einmalig den ersten Marketingversion-Tag setzen:

```sh
make bump-version VERSION=0.0.2
```

Und den Nightly-Workflow manuell anstoßen, statt bis zum nächsten geplanten
Lauf zu warten: **Actions → Nightly → Run workflow**. Der komplette Ablauf
(Tag-Schema, Buildnummer-Reservierung, `testflight-last`) steht in
[docs/release.md](release.md).

Häufige Fehlschläge beim ersten Mal:

| Meldung | Ursache |
| --- | --- |
| `Could not find app with bundle identifier` | App-Datensatz in ASC fehlt (siehe oben) |
| `Authentication credentials are missing or invalid` | `MATCH_GIT_TOKEN` ist der rohe Token statt base64 von `user:token`, oder mit Zeilenumbruch |
| `No profile for team … matching … found` | `match appstore` wurde für diese Bundle-ID noch nicht gelaufen |
| `Invalid curve name` / p8 unlesbar | `ASC_KEY_P8` ist nicht base64, oder beim Kopieren umgebrochen |
| `Kein vX.Y.Z-Tag in der Historie gefunden` | `make bump-version VERSION=0.0.2` wurde noch nicht ausgeführt |
| `The provided entity includes an attribute with a value that has already been used` | Sollte durch die atomare Buildnummer-Reservierung nicht mehr vorkommen; falls doch, wurde die App vorher schon manuell mit dieser Nummer bespielt — der nächste Nightly-Lauf zählt automatisch weiter |
