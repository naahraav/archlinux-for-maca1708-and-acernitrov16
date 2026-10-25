#!/usr/bin/env bash
set -euo pipefail

# GUI-only entry point: choose the installed desktop before opening Calamares.
# This persists the choice for a future Calamares shellprocess hook; it does not
# itself install packages or claim that the selection has been applied.
CHOICE_FILE=/var/lib/arch-v3/desktop-choice
mkdir -p "$(dirname "$CHOICE_FILE")"
choice="$(zenity --list --radiolist \
  --title='Arch Linux V3 — Pilih Desktop' \
  --text='Pilih satu desktop untuk sistem yang akan dipasang. Live USB tetap memakai XFCE.' \
  --column='Pilih' --column='Desktop' \
  TRUE 'KDE Plasma' FALSE 'GNOME' FALSE 'XFCE' FALSE 'Hyprland' \
  --height=300 --width=520)" || exit 0
case "$choice" in
  'KDE Plasma') value=kde ;;
  GNOME) value=gnome ;;
  XFCE) value=xfce ;;
  Hyprland) value=hyprland ;;
  *) exit 1 ;;
esac
printf '%s\n' "$value" > "$CHOICE_FILE"
zenity --question --title='Calamares belum dikonfigurasi penuh' \
  --text="Pilihan desktop tersimpan: $choice.\n\nKonfigurasi pemasangan Calamares untuk menerapkan pilihan ini harus diverifikasi pada build ISO dan VM. Lanjutkan membuka Calamares?" \
  --ok-label='Buka Calamares' --cancel-label='Batal' || exit 0
exec pkexec calamares
