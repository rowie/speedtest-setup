#!/bin/bash

# .env laden
if [ ! -f .env ]; then
    echo "❌ Keine .env gefunden!"
    echo "👉 cp .env.example .env && nano .env"
    exit 1
fi
source .env

INSTALL_DIR="$HOME/speedtest"
USER_HOME="$HOME"
CURRENT_USER=$(whoami)

echo "🔧 Installiere Abhängigkeiten..."
sudo apt-get update -qq
sudo apt-get install -y jq msmtp msmtp-mta ca-certificates curl

# Zeitzone setzen
echo "🕐 Setze Zeitzone auf $TIMEZONE..."
sudo timedatectl set-timezone "$TIMEZONE"

# Alte Speedtest-Versionen entfernen
echo "🧹 Entferne alte Speedtest-Versionen..."
sudo rm -f /etc/apt/sources.list.d/speedtest.list
sudo rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list
sudo apt-get remove -y speedtest-cli 2>/dev/null
sudo apt-get remove -y speedtest 2>/dev/null

# Speedtest CLI (Ookla) installieren
echo "📦 Installiere Ookla Speedtest CLI..."

# OS-Version erkennen
OS_ID=$(grep "^ID=" /etc/os-release | cut -d'=' -f2)
OS_VERSION=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2)

# Ubuntu 24.04 (noble) → jammy erzwingen
if [ "$OS_ID" = "ubuntu" ] && [ "$OS_VERSION" = "noble" ]; then
    echo "⚠️  Ubuntu 24.04 erkannt – verwende Jammy-Repository..."
    REPO_CODENAME="jammy"
else
    REPO_CODENAME="$OS_VERSION"
fi

curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash

# Repository auf richtigen Codename setzen
sudo sed -i "s|/ubuntu/ noble|/ubuntu/ $REPO_CODENAME|g" /etc/apt/sources.list.d/ookla_speedtest-cli.list 2>/dev/null
sudo sed -i "s|/ubuntu/ noble|/ubuntu/ $REPO_CODENAME|g" /etc/apt/sources.list.d/speedtest.list 2>/dev/null

sudo apt-get update -qq
sudo apt-get install -y speedtest

# Verzeichnisse anlegen
echo "📁 Erstelle Verzeichnisse..."
mkdir -p "$INSTALL_DIR/results"

# msmtp Konfiguration
echo "📬 Konfiguriere msmtp..."
cat > ~/.msmtprc << MSMTP
defaults
auth           on
tls            on
tls_starttls   off
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        $USER_HOME/.msmtp.log

account        default
host           $MAIL_HOST
port           $MAIL_PORT
from           $MAIL_FROM
user           $MAIL_USER
password       $MAIL_PASS
MSMTP
chmod 600 ~/.msmtprc

# ==========================================
# measure.sh erstellen
# ==========================================
echo "📝 Erstelle measure.sh..."
cat > "$INSTALL_DIR/measure.sh" << MEASURE
#!/bin/bash

RESULTS_DIR="$INSTALL_DIR/results"
CSV_FILE="$INSTALL_DIR/results/speedtest.csv"

DATE=\$(date '+%Y-%m-%d')
TIME=\$(date '+%H:%M')

if [ ! -f "\$CSV_FILE" ]; then
    echo "Datum,Uhrzeit,Download_Mbit,Upload_Mbit,Ping_ms,Server" > "\$CSV_FILE"
fi

echo "🚀 Starte Speedtest..."
RESULT=\$(speedtest --accept-license --accept-gdpr -f json 2>/dev/null)

if [ \$? -ne 0 ] || [ -z "\$RESULT" ]; then
    echo "❌ Speedtest fehlgeschlagen!"
    exit 1
fi

DOWNLOAD=\$(echo "\$RESULT" | jq -r '.download.bandwidth' | awk '{printf "%.1f", \$1/125000}')
UPLOAD=\$(echo "\$RESULT" | jq -r '.upload.bandwidth' | awk '{printf "%.1f", \$1/125000}')
PING=\$(echo "\$RESULT" | jq -r '.ping.latency' | awk '{printf "%.1f", \$1}')
SERVER=\$(echo "\$RESULT" | jq -r '.server.name')

if [ -z "\$DOWNLOAD" ] || [ "\$DOWNLOAD" = "null" ]; then
    echo "❌ Ungültige Messwerte!"
    exit 1
fi

echo "\$DATE,\$TIME,\$DOWNLOAD,\$UPLOAD,\$PING,\$SERVER" >> "\$CSV_FILE"
echo "✅ \$DATE \$TIME | ⬇ \$DOWNLOAD Mbit/s | ⬆ \$UPLOAD Mbit/s | 🏓 \$PING ms | \$SERVER"

THRESHOLD=$DAILY_THRESHOLD
MAIL_TO="$MAIL_TO"
DEVICE_NAME="$DEVICE_NAME"

DOWN_INT=\$(echo "\$DOWNLOAD" | cut -d'.' -f1)
if [ "\$DOWN_INT" -lt "\$THRESHOLD" ] 2>/dev/null; then
    SUBJECT="⚠️ [\$DEVICE_NAME] Langsames Internet: \$DOWNLOAD Mbit/s"
    BODY="Warnung von \$DEVICE_NAME!

Zeitpunkt:  \$DATE \$TIME
Download:   \$DOWNLOAD Mbit/s (Schwellenwert: \$THRESHOLD Mbit/s)
Upload:     \$UPLOAD Mbit/s
Ping:       \$PING ms
Server:     \$SERVER

================================================
\$DEVICE_NAME Speedcheck"
    echo "\$BODY" | msmtp -a default "\$MAIL_TO" <<MAIL
From: \$DEVICE_NAME Speedcheck <$MAIL_FROM>
To: \$MAIL_TO
Subject: \$SUBJECT

\$BODY
MAIL
    echo "⚠️  Warnung gesendet!"
fi
MEASURE
chmod +x "$INSTALL_DIR/measure.sh"

# ==========================================
# report.sh erstellen
# ==========================================
echo "📝 Erstelle report.sh..."
cat > "$INSTALL_DIR/report.sh" << REPORT
#!/bin/bash

CSV_FILE="$INSTALL_DIR/results/speedtest.csv"
TODAY=\$(date '+%Y-%m-%d')
MAIL_TO="$MAIL_TO"
DEVICE_NAME="$DEVICE_NAME"
MAIL_FROM="$MAIL_FROM"

if [ ! -f "\$CSV_FILE" ]; then
    echo "❌ Keine Messdaten gefunden!"
    exit 1
fi

TODAY_DATA=\$(grep "^\$TODAY" "\$CSV_FILE")

if [ -z "\$TODAY_DATA" ]; then
    echo "❌ Keine Daten für heute (\$TODAY) gefunden!"
    exit 1
fi

AVG_DOWN=\$(echo "\$TODAY_DATA" | awk -F',' '{sum+=\$3; count++} END {printf "%.1f", sum/count}')
AVG_UP=\$(echo "\$TODAY_DATA"   | awk -F',' '{sum+=\$4; count++} END {printf "%.1f", sum/count}')
AVG_PING=\$(echo "\$TODAY_DATA" | awk -F',' '{sum+=\$5; count++} END {printf "%.1f", sum/count}')
MAX_DOWN=\$(echo "\$TODAY_DATA" | awk -F',' 'BEGIN{max=0} {if(\$3>max) max=\$3} END {printf "%.1f", max}')
MIN_DOWN=\$(echo "\$TODAY_DATA" | awk -F',' 'BEGIN{min=99999} {if(\$3<min) min=\$3} END {printf "%.1f", min}')
MAX_UP=\$(echo "\$TODAY_DATA"   | awk -F',' 'BEGIN{max=0} {if(\$4>max) max=\$4} END {printf "%.1f", max}')
MIN_UP=\$(echo "\$TODAY_DATA"   | awk -F',' 'BEGIN{min=99999} {if(\$4<min) min=\$4} END {printf "%.1f", min}')
COUNT=\$(echo "\$TODAY_DATA" | wc -l)

BAR_CHART=\$(echo "\$TODAY_DATA" | awk -F',' '{
    val = \$3
    bar_len = int(val / 2)
    bar = ""
    for (i=0; i<bar_len; i++) bar = bar "█"
    printf "%s | %-30s %.1f Mbit/s\n", \$2, bar, val
}')

BAR_CHART_UP=\$(echo "\$TODAY_DATA" | awk -F',' '{
    val = \$4
    bar_len = int(val / 2)
    bar = ""
    for (i=0; i<bar_len; i++) bar = bar "█"
    printf "%s | %-30s %.1f Mbit/s\n", \$2, bar, val
}')

SUBJECT="📊 [\$DEVICE_NAME] Tagesbericht \$TODAY"

BODY="════════════════════════════════════════════════
  \$DEVICE_NAME – Speedtest Tagesbericht
  \$TODAY | \$COUNT Messungen
════════════════════════════════════════════════

📊 ZUSAMMENFASSUNG
--------------------------------------------------
⬇ Download:  Ø \${AVG_DOWN} Mbit/s  (Min: \${MIN_DOWN} / Max: \${MAX_DOWN})
⬆ Upload:    Ø \${AVG_UP} Mbit/s    (Min: \${MIN_UP} / Max: \${MAX_UP})
🏓 Ping:      Ø \${AVG_PING} ms

📈 DOWNLOAD VERLAUF
--------------------------------------------------
\$BAR_CHART

📤 UPLOAD VERLAUF
--------------------------------------------------
\$BAR_CHART_UP

📋 ALLE MESSUNGEN
--------------------------------------------------
\$(echo "\$TODAY_DATA" | awk -F',' '{printf "%-8s | ⬇ %-8s | ⬆ %-8s | 🏓 %-6s | %s\n", \$2, \$3" Mbit/s", \$4" Mbit/s", \$5" ms", \$6}')

════════════════════════════════════════════════
\$DEVICE_NAME Speedcheck"

echo "\$BODY" | msmtp -a default "\$MAIL_TO" <<MAIL
From: \$DEVICE_NAME Speedcheck <\$MAIL_FROM>
To: \$MAIL_TO
Subject: \$SUBJECT
Content-Type: text/plain; charset=UTF-8

\$BODY
MAIL

if [ \$? -eq 0 ]; then
    echo "✅ Tagesbericht gesendet an \$MAIL_TO"
else
    echo "❌ E-Mail konnte nicht gesendet werden!"
fi
REPORT
chmod +x "$INSTALL_DIR/report.sh"

# ==========================================
# Cronjobs einrichten
# ==========================================
echo "⏰ Richte Cronjobs ein..."
(crontab -l 2>/dev/null | grep -v "speedtest"; cat << CRON
$CRON_MEASURE_1 $INSTALL_DIR/measure.sh >> $INSTALL_DIR/measure.log 2>&1
$CRON_MEASURE_2 $INSTALL_DIR/measure.sh >> $INSTALL_DIR/measure.log 2>&1
$CRON_MEASURE_3 $INSTALL_DIR/measure.sh >> $INSTALL_DIR/measure.log 2>&1
$CRON_REPORT    $INSTALL_DIR/report.sh  >> $INSTALL_DIR/report.log  2>&1
CRON
) | crontab -

# ==========================================
# Abschluss
# ==========================================
echo ""
echo "✅ Setup abgeschlossen!"
echo "=================================="
echo "  Gerät:    $DEVICE_NAME"
echo "  Benutzer: $CURRENT_USER"
echo "  Pfad:     $INSTALL_DIR"
echo "  Zeitzone: $TIMEZONE"
echo "  Mail an:  $MAIL_TO"
echo "=================================="
echo ""
echo "🧪 Jetzt testen:"
echo "   $INSTALL_DIR/measure.sh"
echo "   $INSTALL_DIR/report.sh"
echo ""
echo "📧 Testmail:"
echo "   echo 'Test' | msmtp $MAIL_TO"
echo ""
echo "📋 Cronjobs:"
echo "   crontab -l"
echo ""
echo "📄 Logs:"
echo "   tail -f $INSTALL_DIR/measure.log"
echo "   tail -f $INSTALL_DIR/report.log"
