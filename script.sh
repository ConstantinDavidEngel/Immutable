#!/bin/bash

# CLBK Server setup Script
# COEN - 13.12.2024
# V 1.0.0

# Stoppt das Script bei einem Fehler
set -e

# Help funktion
function show_help() {
    echo "Verwendung: $0 <passwort>"
    echo
    echo "Dieses Skript richtet ein CLBK-Server ein und führt die notwendigen Konfigurationen durch."
    echo
    echo "Optionen:"
    echo "  -h, --help    Zeigt diese Hilfe an."
    echo
    echo "Beispiel:"
    echo "  $0 MeinSicheresPasswort"
    exit 0
}

# Überprüft die Benutzereingabe
if [[ "$#" -ne 1 && "$1" != "-h" && "$1" != "--help" ]]; then
    echo "Bitte ein Passwort als Argument angeben."
    echo "Benutzung: $0 <passwort>"
    exit 1
elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# Funktion zum Anzeigen des Status
function status_message() {
    echo -n "$1"
}

# Funktion zum Anzeigen des Status des beendeten Befehls
function success_message() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "\e[32m [ Erfolgreich ]\e[0m"
    else
        echo -e "\e[31m [ Fehlgeschlagen ]\e[0m"
        echo "Fehler während der Ausführung. Fehlercode: $exit_code"
        exit $exit_code
    fi
}

# Funktion zur Ausführung eines Befehls mit Statusanzeige
function run_command() {
    "$@"
    success_message
}

# Variablen setzen
PASSWORD=$1
SERVERNAME=$(hostname)

# Sudo Rechte erhalten
status_message "Erhalte Root-Rechte"
run_command sudo -s

# Paketkatalog aktualisieren
status_message "Paketkatalog updaten"
run_command apt update

# Installierte Pakete & update Distribution
status_message "Installiere Pakete und Distribution update"
run_command apt upgrade -y && apt dist-upgrade -y

# Zusätzliche Pakete installieren
status_message "Installiere zusätzliche Pakete"
run_command apt install -y nano net-tools iputils-ping chrony glances

# Erstelle PBKDF2-Hash für GRUB Passwort
status_message "Erstelle PBKDF2-Hash für GRUB Passwort"
PBKDF2_HASH=$(echo "$PASSWORD" | grub-mkpasswd-pbkdf2 | grep "PBKDF2")
success_message

# GRUB Konfiguration anpassen
status_message "Anpassung der GRUB-Konfiguration"
{
    echo 'set superusers="root"'
    echo "password_pbkdf2 root ${PBKDF2_HASH#*:}" # Führe nur den Hash ein, ohne den "PBKDF2" Teil
} | run_command sudo tee -a /etc/grub.d/40_custom

# 10_linux Datei anpassen um --unrestricted hinzuzufügen
status_message "Aktualisiere /etc/grub.d/10_linux Datei"
run_command sudo sed -i 's/CLASS="--class gnu-linux --class gnu --class os"/CLASS="--class gnu-linux --class gnu --class os --unrestricted"/' /etc/grub.d/10_linux

# GRUB Boot Menü aktivieren
status_message "Aktiviere GRUB Boot-Menü"
run_command sudo sed -i 's/GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
run_command sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=10/' /etc/default/grub

# GRUB-Konfiguration aktualisieren
status_message "Aktualisiere GRUB-Konfiguration"
run_command sudo update-grub

# Berechtigungen für Backup Verzeichnis setzen
status_message "Setze Berechtigungen für das Backup-Verzeichnis"
run_command sudo chown -R sa_${SERVERNAME}:sa_${SERVERNAME} /mnt/backup/
run_command sudo chmod 700 /mnt/backup/

# Berechtigungen für reboot und shutdown setzen
status_message "Erteile Berechtigungen für reboot und shutdown"
{
    echo "sa_${SERVERNAME} ALL = (root) NOEXEC: /usr/sbin/reboot"
    echo "sa_${SERVERNAME} ALL = (root) NOEXEC: /usr/sbin/shutdown"
} | run_command sudo tee -a /etc/sudoers

# Deaktivieren nicht benötigter Netzwerkinterfaces im Netplan
echo "Netzwerk Interfaces müssen manuell eingestellt werden"

# Hardening mittels Veeam Script
status_message "Lade Veeam Hardening Script herunter und führe es aus"
cd /tmp
run_command curl -s https://raw.githubusercontent.com/VeeamHub/veeam-hardened-repository/master/veeam.harden.sh -o /tmp/veeam.harden.sh
run_command bash /tmp/veeam.harden.sh >veeam.harden.txt 2>&1

# Zeitkonfiguration
status_message "Setze die Zeitzone und die NTP-Server"
run_command timedatectl set-timezone Europe/Zurich
run_command timedatectl set-ntp off
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
run_command timedatectl set-time "$CURRENT_TIME"
run_command timedatectl set-ntp on

# Script beenden
echo "Script beendet. Bitte führe Punkt 2.7 Teil 3 weiter in der Anleitung aus."
