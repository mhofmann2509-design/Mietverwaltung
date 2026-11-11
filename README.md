# Mietverwaltung

Eine native Swift/SwiftUI-App zur Verwaltung deiner vermieteten Immobilien – läuft als eigenständige App auf dem Mac **und** auf dem iPhone (gleicher Code, zwei Build-Ziele).

## Funktionsumfang

- **Immobilien & Einheiten**: Objekte mit Adresse anlegen, pro Objekt beliebig viele Einheiten (Wohnungen) mit Größe/Zimmerzahl.
- **Mieter & Mietverträge**: Mieterstammdaten, Mietvertrag pro Einheit mit Kaltmiete, Nebenkostenvorauszahlung, Kaution, Laufzeit, Kündigungsfrist.
- **Mieteinnahmen**: Monatsübersicht aller laufenden Mietverhältnisse, Soll/Ist-Abgleich, Zahlungen als bezahlt/offen markieren.
- **Ausgaben**: Reparaturen, Betriebskosten, Versicherung, Steuern etc. – pro Immobilie oder Einheit, mit Beleg-Anhang.
- **Dokumente**: Verträge, Belege, Fotos – mit Verknüpfung zu Immobilie, Einheit, Mieter oder Ausgabe, exportierbar per Teilen-Funktion.
- **Investment-Dashboard**: Kaufpreis, Kaufnebenkosten, Brutto-/Nettorendite pro Immobilie und fürs ganze Portfolio, Wohnfläche und Ausstattungsmerkmale (Balkon, Einbauküche, Stellplatz, …) direkt auf der Übersichtsseite.
- **Steuerliche Betrachtung**: Automatische Gebäude-AfA nach Baujahr (§7 Abs. 4 EStG, mit manuellem Override), separate Abschreibung für Möblierung und Herstellungskosten (Wirtschaftsgüter mit eigener Nutzungsdauer), jede Ausgabe als „sofort abziehbar" (Erhaltungsaufwand) oder „Herstellungskosten" (AfA) einstufbar, geschätztes steuerliches Ergebnis pro Immobilie und Portfolio auf dem Dashboard – mit Jahresauswahl, nicht nur fürs laufende Jahr, auch für die Steuererklärung vergangener Jahre.
- **Mahnwesen**: Bei überfälliger Miete per Wisch-Geste direkt ein Erinnerungsschreiben an den Mieter teilen.
- **CSV-Export**: Alle Ausgaben als CSV für den Steuerberater exportierbar.
- **Belege scannen**: Auf dem iPhone per Kamera scannen (VisionKit), Texterkennung (Vision/OCR) schlägt Belegdatum, Betrag und Titel vor – alle Felder bleiben vor dem Speichern frei korrigierbar. Alternativ Datei-Import (Mac & iPhone). Belege werden nach Belegdatum sortiert, lassen sich nach Steuerjahr filtern und für die Steuererklärung gebündelt wieder abrufen.
- **Nebenkostenabrechnung**: Die jährliche Abrechnung der Hausverwaltung (Kostenarten + Beträge, Original-PDF anhängbar) erfassen – die App verteilt die Kosten automatisch anteilig nach Wohnfläche und Mietdauer auf die Mieter, vergleicht mit den geleisteten Vorauszahlungen und zeigt Nachzahlung/Guthaben je Mieter. Pro Mieter einzeln als Schreiben teilbar oder als Dokument ablegbar, zusätzlich eine Gesamtübersicht. Kostenarten lassen sich auch per Beleg-Foto (OCR), aus einer echten `.xlsx`-Datei oder aus CSV importieren (Wirtschaftsplan ebenso).
- **Anstehende Aufgaben**: Das Dashboard zeigt automatisch überfällige Mietzahlungen, bald endende Mietverträge und die gesetzliche Nebenkostenabrechnungs-Frist (12 Monate nach Ablauf des Abrechnungsjahres) – ohne zusätzliche Eingabe, abgeleitet aus den vorhandenen Daten.
- **Suche**: Immobilien, Mieter, Ausgaben und Dokumente lassen sich jeweils durchsuchen.

Die Daten synchronisieren automatisch über deine eigene private iCloud (CloudKit) zwischen Mac und iPhone, wenn auf beiden Geräten dieselbe Apple-ID angemeldet ist – siehe unten, Abschnitt „iCloud-Sync (CloudKit)", für den dafür nötigen einmaligen Xcode-Schritt und für die datenschutzrechtliche Einordnung.

> **Hinweis:** Die steuerlichen Berechnungen (AfA, Werbungskosten, Nebenkostenverteilung) sind vereinfachte Näherungen zur Orientierung und ersetzen keine Steuerberatung.

## Voraussetzung: Xcode-Lizenz bestätigen

Xcode ist auf diesem Mac bereits installiert. Bevor Xcode irgendetwas bauen kann, muss einmalig die Lizenzvereinbarung bestätigt werden. Das geht nur interaktiv mit deinem Mac-Passwort, führ daher bitte einmal in einem Terminal aus:

```bash
sudo xcodebuild -license
```

Mit der Leertaste durch den Text blättern, am Ende mit `agree` bestätigen.

Falls du anschließend auch mit deiner Apple-ID in Xcode arbeiten willst (für Signierung auf deinem iPhone und optional iCloud-Sync): **Xcode → Settings → Accounts** → Apple-ID hinzufügen (reicht als „Personal Team", kein kostenpflichtiges Entwicklerkonto nötig, um die App auf deinen eigenen Geräten zu testen).

## Projekt öffnen

```bash
open Mietverwaltung.xcodeproj
```

Es gibt zwei Targets/Schemes:
- **Mietverwaltung-iOS** → für iPhone (Simulator oder dein eigenes iPhone)
- **Mietverwaltung-macOS** → für den Mac

Beim ersten Öffnen für jedes Target einmal einstellen:
1. Projekt anklicken → Target wählen → Tab **Signing & Capabilities**.
2. Bei **Team** deine Apple-ID (Personal Team) auswählen. Xcode vergibt dann automatisch ein Signing-Zertifikat.

Danach oben das gewünschte Scheme (iOS oder macOS) auswählen, Zielgerät wählen (dein iPhone per Kabel/WLAN, ein iOS-Simulator, oder „My Mac") und auf ▶️ **Run** klicken.

> Um auf dem **echten iPhone** zu laufen (nicht nur Simulator), muss das iPhone einmal per Kabel verbunden und in den Entwickler-Einstellungen (Einstellungen → Allgemein → VPN & Geräteverwaltung) der eigenen Apple-ID vertraut werden – Xcode führt dich beim ersten Run automatisch durch diesen Schritt.

## iCloud-Sync (CloudKit)

Die App ist für automatische Synchronisierung über CloudKit vorbereitet: `Sources/MietverwaltungApp.swift` nutzt `cloudKitDatabase: .automatic`, und beide Targets haben die nötigen iCloud-Entitlements (`Mietverwaltung-iOS.entitlements`/`Mietverwaltung-macOS.entitlements`, Container `iCloud.com.marcelhofmann.mietverwaltung`, siehe `project.yml`). Es fehlt nur noch ein einmaliger, zwingend interaktiver Schritt, den nur du in Xcode machen kannst (er erfordert deine angemeldete Apple-ID):

1. Projekt öffnen, für **beide** Targets (iOS und macOS) → Tab **Signing & Capabilities** → bei **Team** deine Apple-ID (Personal Team reicht) auswählen, falls noch nicht geschehen.
2. Einmal bauen/ausführen (▶️). Xcode registriert beim ersten Build mit ausgewähltem Team automatisch den iCloud-Container `iCloud.com.marcelhofmann.mietverwaltung` in deinem Apple-Entwicklerkonto (du siehst dafür ggf. kurz eine Rückfrage/einen Ladehinweis in Xcode).
3. Auf dem zweiten Gerät (Mac bzw. iPhone) genauso verfahren, jeweils mit **derselben Apple-ID** angemeldet (iCloud-Account, nicht zwingend dasselbe wie der Xcode-Entwickler-Account, siehe unten).

**Ohne diesen Schritt baut das Projekt nicht**, da die Entitlements ein echtes Entwickler-Zertifikat verlangen (Fehlermeldung „entitlements that require signing with a development certificate"). Um versuchsweise wieder rein lokal zu arbeiten, ohne Team: die beiden `properties:`-Blöcke unter `entitlements:` in `project.yml` entfernen, `cloudKitDatabase: .automatic` in `MietverwaltungApp.swift` wieder löschen und `xcodegen generate` erneut ausführen.

**Hinweis bei kostenlosem Apple-Konto (Personal Team):** In seltenen Fällen verlangt Xcode hier ein kostenpflichtiges Apple Developer Program-Konto (99 $/Jahr) – betrifft i.d.R. nur bestimmte Capabilities, nicht grundsätzlich CloudKit für den Eigenbedarf. Tritt das auf, hilft nur ein Upgrade des Kontos oder der Rückbau wie oben beschrieben.

### Wie funktioniert das datenschutzrechtlich?

- **Es ist deine eigene private iCloud, kein fremder Server dieses Projekts.** CloudKit speichert ausschließlich in der **privaten Datenbank** des Containers (`cloudKitDatabase: .automatic` nutzt nie die "öffentliche" CloudKit-Datenbank) – das heißt: die Daten landen in deinem persönlichen iCloud-Speicherkontingent, verschlüsselt auf Apples Servern, und sind nur für Geräte sichtbar, die mit **derselben Apple-ID** angemeldet sind. Niemand sonst (auch nicht andere Nutzer dieser App, falls du sie weitergibst) sieht deine Daten – jeder Nutzer bekäme seinen eigenen, komplett getrennten CloudKit-Container-Bereich.
- **Kein Entwickler-Zugriff.** Weder ich (als Autor dieser Session) noch irgendein Betreiber können auf deine CloudKit-Daten zugreifen – es gibt keinen eigenen Server, kein Backend, keine Analytics; Apple selbst behandelt CloudKit-Private-Database-Inhalte nach seinen iCloud-Datenschutzzusagen (Ende-zu-Ende-verschlüsselt für viele Datentypen, grundsätzlich aber je nach Datentyp unterschiedlich – für diese App nicht Advanced-Data-Protection-pflichtig, da keine besonders sensiblen Kategorien wie Gesundheitsdaten).
- **Rechtsgrundlage/Verantwortlichkeit:** Du bist bei dieser Konstellation faktisch dein eigener Auftragsverarbeiter – es gibt keinen Dritten, dem Mieter- oder Finanzdaten "mitgeteilt" werden, außer Apple als technischem Cloud-Infrastrukturanbieter (vergleichbar mit der Nutzung von iCloud für Fotos/Notizen). Für DSGVO-Zwecke bist du selbst verantwortliche Stelle für die Verarbeitung der Mieterdaten; Apple fungiert als Auftragsverarbeiter gemäß seinen eigenen iCloud-AGB/DPA. Das ist keine Rechtsberatung – bei Unsicherheit bei einem Datenschutzbeauftragten/Anwalt erfragen, insbesondere wenn du gewerblich (nicht nur privat) vermietest.
- **Offline-Verhalten:** Ohne Internetverbindung funktioniert die App unverändert lokal weiter (SwiftData cached lokal, CloudKit synchronisiert nur im Hintergrund, sobald wieder online).

### Deine iCloud-Drive-Ordner-Frage

Du hast erwähnt, dass der Projektordner selbst (`MietverwaltungsApp`, also der Quellcode-Ordner, den Xcode öffnet) in iCloud Drive liegt. Das ist etwas **anderes** als der hier beschriebene CloudKit-Sync und synchronisiert **nicht** die App-Daten:

- **Projektordner in iCloud Drive** synchronisiert nur die Quellcode-/Projektdateien zwischen deinen Macs (falls du auf mehreren Macs mit Xcode arbeitest) – das iPhone kann damit ohnehin nichts anfangen, da dort kein Xcode läuft und die App-Datenbank (SwiftData-Store) nicht im Projektordner liegt, sondern im app-eigenen, sandboxed Containerverzeichnis des jeweiligen Geräts.
- **CloudKit-Sync (dieser Abschnitt)** ist der tatsächliche Mechanismus, der die **App-internen Daten** (Immobilien, Mieter, Dokumente, Belege, …) zwischen Mac und iPhone abgleicht – unabhängig davon, wo der Xcode-Projektordner liegt.

Kurz: Ja, „über deine eigene iCloud" funktioniert die Synchronisierung – aber über CloudKit (wie oben beschrieben), nicht automatisch dadurch, dass der Projektordner in iCloud Drive liegt.

## Projektstruktur ändern

Das Projekt wird mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) aus `project.yml` erzeugt (zuverlässiger als eine von Hand gepflegte `.xcodeproj`). **Nach jeder neuen Datei im `Sources`- oder `Tests`-Ordner und nach jeder Änderung an `project.yml`** (Build-Einstellungen, neue Targets, Pakete, Entitlements o. Ä.) einmal ausführen – die `.xcodeproj` wird sonst nicht aktualisiert und die neue Datei fehlt im Build:

```bash
brew install xcodegen   # falls noch nicht installiert
xcodegen generate
```

## Code-Überblick

```
Sources/
  MietverwaltungApp.swift      – App-Einstiegspunkt, SwiftData-Setup
  ContentView.swift            – Seitenleiste/Navigation
  Models/                      – SwiftData-Modelle (Property, Unit, Tenant, Tenancy, RentPayment, Expense, Document)
  Views/
    Dashboard/                 – Übersicht/Kennzahlen
    Properties/                – Immobilien, Einheiten, Mietverträge
    Tenants/                   – Mieterverwaltung
    Payments/                  – Monatliche Mietzahlungen erfassen
    Expenses/                  – Ausgaben
    Documents/                 – Dokumentenablage
  Support/                     – Formatierung, Preview-Beispieldaten
```

Da auf diesem Rechner kein vollständiges Xcode installiert ist, konnte der Code hier nicht tatsächlich kompiliert werden (nur syntaktisch geprüft) – beim ersten Build in Xcode können daher ggf. noch kleine Korrekturen nötig sein. Melde mir einfach jeden Compiler-Fehler, den Xcode anzeigt, dann behebe ich ihn.
