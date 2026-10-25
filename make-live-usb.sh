#!/usr/bin/env bash
# ==============================================================================
# Menulis ISO Arch V3 ke flashdisk (Live USB) dari Linux atau macOS.
#
#   sudo ./make-live-usb.sh                       # cari .iso otomatis, pilih USB interaktif
#   sudo ./make-live-usb.sh file.iso /dev/sdX     # langsung (Linux)
#   sudo ./make-live-usb.sh file.iso disk4        # langsung (macOS)
#
# Windows: pakai Rufus (mode "DD Image") atau balenaEtcher.
# ==============================================================================
set -euo pipefail

die() { echo "[GAGAL] $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

OS=$(uname -s)
ISO="${1:-}"
TARGET="${2:-}"

# --- Cari ISO ----------------------------------------------------------------
if [[ -z $ISO ]]; then
    ISO=$(ls -t ./*.iso ./out-iso/*.iso 2>/dev/null | head -n1 || true)
    [[ -n $ISO ]] || die "File .iso tidak ditemukan. Pakai: $0 path/ke/file.iso"
    echo "ISO: $ISO"
fi
[[ -f $ISO ]] || die "File tidak ada: $ISO"

# --- Verifikasi checksum (jika ada file .sha256 di sebelahnya) ----------------
if [[ -f "$ISO.sha256" ]]; then
    echo "Memverifikasi checksum..."
    if command -v sha256sum &>/dev/null; then
        (cd "$(dirname "$ISO")" && sha256sum -c "$(basename "$ISO").sha256")
    else
        (cd "$(dirname "$ISO")" && shasum -a 256 -c "$(basename "$ISO").sha256")
    fi
else
    echo "(Tidak ada file .sha256, verifikasi checksum dilewati.)"
fi

# ==============================================================================
if [[ $OS == "Darwin" ]]; then
    # ------------------------------ macOS -------------------------------------
    if [[ -z $TARGET ]]; then
        diskutil list external physical
        read -rp "Nama disk USB (contoh: disk4): " TARGET
    fi
    TARGET="${TARGET#/dev/}"; TARGET="${TARGET#r}"
    [[ $TARGET =~ ^disk[0-9]+$ ]] || die "Nama disk tidak valid: $TARGET"
    diskutil info "$TARGET" | grep -qiE 'Removable Media: *(Removable|Yes)|Device Location: *External' \
        || die "$TARGET tidak terdeteksi sebagai disk eksternal. Dibatalkan demi keamanan."

    diskutil info "$TARGET" | grep -E 'Device / Media Name|Disk Size'
    echo "SEMUA DATA di /dev/$TARGET akan DIHAPUS."
    read -rp "Ketik nama disk ($TARGET) untuk konfirmasi: " c
    [[ $c == "$TARGET" ]] || die "Dibatalkan."

    diskutil unmountDisk "/dev/$TARGET"
    echo "Menulis... (tekan Ctrl+T untuk melihat progres)"
    dd if="$ISO" of="/dev/r$TARGET" bs=4m
    sync
    diskutil eject "/dev/$TARGET" || true
else
    # ------------------------------ Linux -------------------------------------
    if [[ -z $TARGET ]]; then
        echo "Perangkat USB/removable yang terdeteksi:"
        mapfile -t CANDS < <(lsblk -dpno NAME,SIZE,MODEL,TRAN,RM,TYPE | awk '$NF=="disk" && ($(NF-1)=="1" || tolower($0) ~ /usb/)')
        ((${#CANDS[@]} > 0)) || die "Tidak ada USB terdeteksi. Colok flashdisk atau berikan path manual."
        i=1
        for l in "${CANDS[@]}"; do printf "  %d) %s\n" "$i" "$(echo "$l" | tr -s ' ')"; i=$((i + 1)); done
        read -rp "Pilih nomor: " n
        [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#CANDS[@]})) || die "Pilihan tidak valid."
        TARGET=$(echo "${CANDS[$((n - 1))]}" | awk '{print $1}')
    fi
    [[ -b $TARGET ]] || die "$TARGET bukan block device."
    [[ $(lsblk -dno TYPE "$TARGET") == "disk" ]] || die "$TARGET harus berupa disk utuh (mis. /dev/sdb), bukan partisi."

    # Jangan pernah menulis ke disk tempat sistem berjalan
    ROOT_SRC=$(findmnt -no SOURCE / || true)
    ROOT_DISK="/dev/$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1 || true)"
    [[ $TARGET != "$ROOT_DISK" ]] || die "$TARGET adalah disk sistem yang sedang berjalan. Dibatalkan."

    lsblk -po NAME,SIZE,MODEL,TRAN "$TARGET"
    echo "SEMUA DATA di $TARGET akan DIHAPUS."
    read -rp "Ketik path perangkat ($TARGET) untuk konfirmasi: " c
    [[ $c == "$TARGET" ]] || die "Dibatalkan."

    for p in $(lsblk -lnpo NAME "$TARGET" | tail -n +2); do umount "$p" 2>/dev/null || true; done

    dd if="$ISO" of="$TARGET" bs=4M conv=fsync oflag=direct status=progress
    sync

    echo "Memverifikasi hasil tulis..."
    SIZE=$(stat -c%s "$ISO")
    if cmp -n "$SIZE" "$ISO" "$TARGET"; then
        echo "Verifikasi OK."
    else
        die "Verifikasi GAGAL: data di USB berbeda dari ISO. Coba ulangi / ganti flashdisk."
    fi
fi

echo
echo "Live USB siap. Cabut flashdisk dengan aman."
echo "  MacBook A1708 : tahan tombol Option saat menyalakan -> pilih 'EFI Boot'"
echo "  Acer Nitro V16: tekan F2 (BIOS) / F12 (boot menu); matikan Secure Boot dulu"
