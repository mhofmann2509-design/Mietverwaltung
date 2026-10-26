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
- **Nebenkostenabrechnung**: Die jährliche Abrechnung der Hausverwaltung (Kostenarten + Beträge, Original-PDF anhängbar) erfassen – die App verteilt die Kosten automatisch anteilig nach Wohnfläche und Mietdauer auf die Mieter, vergleicht mit den geleisteten Vorauszahlungen und zeigt Nachzahlung/Guthaben je Mieter. Pro Mieter einzeln als Schreiben teilbar oder als Dokument ablegbar, zusätzlich eine Gesamtübersicht.
- **Anstehende Aufgaben**: Das Dashboard zeigt automatisch überfällige Mietzahlungen, bald endende Mietverträge und die gesetzliche Nebenkostenabrechnungs-Frist (12 Monate nach Ablauf des Abrechnungsjahres) – ohne zusätzliche Eingabe, abgeleitet aus den vorhandenen Daten.
- **Suche**: Immobilien, Mieter, Ausgaben und Dokumente lassen sich jeweils durchsuchen.

Die Daten liegen lokal auf dem jeweiligen Gerät (SwiftData). Siehe unten, wie du optional automatische Synchronisierung zwischen Mac und iPhone über iCloud aktivierst.

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

## iCloud-Sync aktivieren (optional)

Standardmäßig speichert die App Daten nur lokal auf dem jeweiligen Gerät (Mac und iPhone haben also getrennte Datenbestände). Damit beide Geräte automatisch denselben Datenbestand sehen:

1. Für **beide** Targets (iOS und macOS) in **Signing & Capabilities** auf **+ Capability** klicken → **iCloud** hinzufügen → Haken bei **CloudKit** setzen. Xcode legt automatisch einen passenden iCloud-Container an (für beide Targets denselben Container auswählen).
2. In [`Sources/MietverwaltungApp.swift`](Sources/MietverwaltungApp.swift) die `ModelConfiguration` um CloudKit erweitern:

   ```swift
   let modelConfiguration = ModelConfiguration(
       schema: schema,
       isStoredInMemoryOnly: false,
       cloudKitDatabase: .automatic
   )
   ```
3. Erneut auf Mac und iPhone ausführen, jeweils mit derselben Apple-ID (iCloud) angemeldet.

**Hinweis:** Mit einem kostenlosen Apple-Konto (Personal Team) kann es bei der iCloud-Capability zu Einschränkungen kommen. Falls Xcode hier eine Fehlermeldung zeigt, die ein kostenpflichtiges Apple Developer Program-Konto (99 $/Jahr) verlangt, funktioniert die App trotzdem weiterhin **ohne** Sync – einfach Schritt 2 wieder zurücksetzen.

## Projektstruktur ändern

Das Projekt wird mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) aus `project.yml` erzeugt (zuverlässiger als eine von Hand gepflegte `.xcodeproj`). Wenn du neue Swift-Dateien im `Sources`-Ordner hinzufügst, werden sie automatisch erkannt – du musst dafür **nicht** `xcodegen` erneut aufrufen. Nur wenn du Build-Einstellungen, neue Targets o. Ä. in `project.yml` änderst, einmal ausführen:

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
