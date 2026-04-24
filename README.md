# Speedtest Monitor

Automatisches Speedtest-Monitoring mit E-Mail-Reports für Linux-Server.

## Was macht es?

- Misst regelmäßig **Download, Upload und Ping** via `speedtest-cli`
- Speichert alle Ergebnisse in einer **CSV-Datei**
- Sendet **tägliche E-Mail-Reports** mit ASCII-Verlaufsdiagramm
- Einfach auf **mehreren Hosts** ausrollbar

## Voraussetzungen

- Linux (Debian/Ubuntu/Raspberry Pi OS)
- Ein **Mailkonto**

## Installation

### 1. Repository klonen

```bash
git clone https://github.com/rowie/speedtest-setup.git
cd speedtest-setup
```

### 2. Konfiguration anpassen

```bash
cp .env.example .env
nano .env
```

Mindestens diese Werte anpassen:

```bash
DEVICE_NAME="MeinGerät"            # Name des Hosts im Report
MAIL_TO="empfaenger@example.com"   # Wer bekommt den Report?
MAIL_USER="absender@example.com"   # Mailkonto
MAIL_PASS="dein-passwort"          # Passwort
```

### 3. Setup ausführen

```bash
bash speedtest-setup.sh
```

Das Skript installiert alle Abhängigkeiten, richtet `msmtp` mit **Port 465 (SSL)** ein und startet das Monitoring automatisch.

## Verwendung

| Aktion | Befehl |
|--------|--------|
| Manueller Speedtest | `~/speedtest/measure.sh` |
| Manuellen Report senden | `~/speedtest/report.sh` |
| Ergebnisse anzeigen | `cat ~/speedtest/results/speedtest.csv` |
| Cronjobs prüfen | `crontab -l` |
| Logs anzeigen | `tail -f ~/speedtest/measure.log` |

## Cronjob-Zeitplan (Standard)

| Job | Zeit |
|-----|------|
| Speedtest messen | 06:00, 12:00, 18:00 Uhr |
| Tagesbericht senden | 20:00 Uhr |

> Anpassbar in der `.env` via `CRON_MEASURE_1/2/3` und `CRON_REPORT`

## Auf weiteren Hosts ausrollen

```bash
scp speedtest-setup.sh .env user@newhost:~
ssh user@newhost "bash speedtest-setup.sh"
```

## Dateistruktur

```
~/speedtest/
├── results/
│   └── speedtest.csv    # Alle Messergebnisse
├── measure.sh            # Speedtest-Skript
├── report.sh             # Report-Skript
├── measure.log           # Messungs-Log
└── report.log            # Report-Log
```

## Hinweise

- SMTP-Server: Dein eigener Mailserver (Port `465` SSL empfohlen)
- Das Passwort wird in `~/.msmtprc` gespeichert (Berechtigungen: 600)
- Die `.env` wird **nicht** ins Repository eingecheckt (`.gitignore`)

