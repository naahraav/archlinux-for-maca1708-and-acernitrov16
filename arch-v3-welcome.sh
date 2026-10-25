#!/usr/bin/env bash
# Layar sambutan Live USB (dipanggil dari /root/.zlogin pada tty1)
vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")

# Layar Retina MacBook membuat font konsol sangat kecil -> perbesar
if [[ $vendor == *Apple* ]]; then
    setfont ter-132n 2>/dev/null || true
fi

clear
cat <<'EOF'
==============================================================================
   ARCH LINUX V3 - LIVE USB
   MacBook Pro A1708  &  Acer Nitro V 16 (Intel + NVIDIA)
==============================================================================

  Anda sedang berada di lingkungan Live (tidak ada yang berubah di disk).

  [Enter]  Mulai instalasi ke disk (installer interaktif)
  [s]      Masuk shell saja (coba-coba, perbaikan, partisi manual)

  Perintah berguna:
    arch-v3-install      jalankan installer kapan saja
    iwctl                sambungkan Wi-Fi
    lsblk                lihat disk

==============================================================================
EOF

read -rp "Pilihan [Enter/s]: " choice
case "${choice,,}" in
    s|shell) echo "Ketik 'arch-v3-install' bila ingin memulai instalasi." ;;
    *)
        if /root/install-arch-live.sh; then
            :
        else
            echo
            echo "Installer berhenti. Perbaiki masalahnya lalu jalankan ulang: arch-v3-install"
        fi
        ;;
esac
