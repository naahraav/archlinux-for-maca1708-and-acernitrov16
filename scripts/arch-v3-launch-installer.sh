#!/usr/bin/env bash
# ==============================================================================
# Arch Linux V3.1 — GUI Installer Wizard (Zenity + XFCE Terminal Execution)
# Memperbaiki bug permission denied (/var/lib/arch-v3) & menghubungkan langsung
# pilihan GUI (Profil Hardware, Desktop Environment, Erase Disk/Partisi, User)
# ke mesin installer install-arch-live.sh.
# ==============================================================================
set -euo pipefail

# 1. Dialog Sambutan Awal
zenity --question \
  --title="Selamat Datang di Arch Linux V3.1 Live USB" \
  --width=540 --height=260 \
  --ok-label="Mulai Instalasi (GUI)" \
  --cancel-label="Coba Live Desktop Dulu" \
  --text="<b>Arch Linux Custom V3.1 — Dual Hardware Edition</b>\n\n• Mendukung penuh <b>Apple MacBook Pro A1708</b> &amp; <b>Acer Nitro V 16 (Intel + NVIDIA)</b>.\n• Anda dapat membuka ikon <b>Install Arch Linux V3</b> di layar Desktop kapan saja.\n• Pastikan sudah tersambung ke Wi-Fi (ikon jaringan di pojok kanan atas panel XFCE) sebelum memulai instalasi.\n\nApakah Anda ingin memulai wizard instalasi sekarang?" || exit 0

# 2. Deteksi & Pilih Profil Hardware
vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
has_nvidia=$(lspci 2>/dev/null | grep -i nvidia || true)

mac_def="TRUE"; acer_def="FALSE"
if [[ "$vendor" == *Acer* || -n "$has_nvidia" ]]; then
    mac_def="FALSE"; acer_def="TRUE"
fi

hw_choice=$(zenity --list --radiolist \
  --title="Langkah 1/6 — Pilih Profil Perangkat Keras" \
  --text="Deteksi sistem: <b>$vendor $product</b>\nPilih profil optimasi driver yang sesuai dengan laptop Anda:" \
  --column="Pilih" --column="Kode" --column="Deskripsi Perangkat Keras" \
  "$mac_def" "macbook_a1708" "Apple MacBook Pro A1708 (SPI Keyboard, CS8409 Audio DSP, FaceTimeHD, Sleep Fix)" \
  "$acer_def" "acer_nitro_v16" "Acer Nitro V 16 (Intel + NVIDIA RTX Optimus, 165Hz+, SOF Audio, Nitro Fan)" \
  --width=680 --height=280) || exit 0

# 3. Pilih Desktop Environment (Seperti CachyOS)
de_choice=$(zenity --list --radiolist \
  --title="Langkah 2/6 — Pilih Desktop Environment" \
  --text="Pilih <b>SATU</b> Desktop Environment yang akan dipasang ke sistem utama Anda (Hemat Storage &amp; RAM):" \
  --column="Pilih" --column="Kode" --column="Deskripsi Desktop Environment" \
  TRUE  "kde"      "KDE Plasma 6 (Modern, kaya fitur, mendukung Wayland, mirip Windows)" \
  FALSE "hyprland" "Hyprland (Tiling Wayland Compositor, animasi mulus, siap pakai)" \
  FALSE "gnome"    "GNOME (Minimalis, elegan, gesture touchpad sangat nyaman)" \
  FALSE "xfce"     "XFCE4 (Sangat ringan, irit baterai &amp; RAM, klasik)" \
  --width=680 --height=320) || exit 0

# 4. Pilih Mode Instalasi Disk (Erase Disk vs Manual Partitioning)
mode_choice=$(zenity --list --radiolist \
  --title="Langkah 3/6 — Mode Partisi & Penyimpanan" \
  --text="Pilih bagaimana Anda ingin menyiapkan partisi penyimpanan:" \
  --column="Pilih" --column="Kode" --column="Keterangan" \
  TRUE  "auto_ext4"  "Erase Disk — Otomatis format bersih seluruh disk (GPT + EFI 512MB + Root EXT4)" \
  FALSE "auto_btrfs" "Erase Disk — Otomatis format bersih seluruh disk (GPT + EFI 512MB + Root BTRFS zstd)" \
  FALSE "manual"     "Manual Partitioning — Buka GParted / atur sendiri (Untuk Dual-Boot macOS/Windows)" \
  --width=700 --height=300) || exit 0

INSTALL_MODE="auto"
FS_TYPE="ext4"
TARGET_DISK=""

if [[ "$mode_choice" == "manual" ]]; then
    INSTALL_MODE="manual"
    if zenity --question --title="Buka GParted?" --width=480 \
        --text="Apakah Anda ingin membuka aplikasi grafis <b>GParted</b> terlebih dahulu untuk membuat/mengatur partisi?\n\nSetelah GParted ditutup, terminal installer akan memandu mount ke /mnt."; then
        sudo gparted || true
    fi
else
    [[ "$mode_choice" == "auto_btrfs" ]] && FS_TYPE="btrfs"
    # Deteksi disk selain Live USB
    LIVE_SRC=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
    LIVE_PK=""
    if [[ -n "$LIVE_SRC" ]]; then
        pk=$(lsblk -no PKNAME "$LIVE_SRC" 2>/dev/null | head -n1 || true)
        LIVE_PK="${pk:+/dev/$pk}"
        [[ -z "$LIVE_PK" ]] && LIVE_PK="$LIVE_SRC"
    fi

    DISK_LIST=()
    first=true
    while read -r d; do
        [[ -n "$LIVE_PK" && "$d" == "$LIVE_PK" ]] && continue
        desc=$(lsblk -dnpo SIZE,TRAN,MODEL "$d" | tr -s ' ')
        if $first; then
            DISK_LIST+=("TRUE" "$d" "$desc")
            first=false
        else
            DISK_LIST+=("FALSE" "$d" "$desc")
        fi
    done < <(lsblk -dnpo NAME,TYPE -e 7,11 | awk '$2=="disk"{print $1}')

    if (( ${#DISK_LIST[@]} == 0 )); then
        zenity --error --width=480 --text="Tidak ditemukan disk internal!\n\n(Pada Acer Nitro V 16: pastikan mode Intel VMD/RST sudah diubah ke AHCI di BIOS)."
        exit 1
    fi

    TARGET_DISK=$(zenity --list --radiolist \
      --title="Langkah 4/6 — Pilih Disk Tujuan (Erase Disk)" \
      --text="<b>PERINGATAN:</b> Seluruh isi disk yang Anda pilih di bawah ini akan dihapus permanen.\n(Flashdisk Live USB sudah disembunyikan secara otomatis):" \
      --column="Pilih" --column="Device" --column="Ukuran &amp; Model Disk" \
      "${DISK_LIST[@]}" \
      --width=650 --height=300) || exit 0
fi

# 5. Form Pembuatan Akun User & Hostname
def_host="arch-nitro"
[[ "$hw_choice" == "macbook_a1708" ]] && def_host="arch-a1708"

while true; do
    form_out=$(zenity --forms \
      --title="Langkah 5/6 — Akun Pengguna & Sistem" \
      --text="Masukkan informasi akun pengguna (sudo) dan nama komputer:" \
      --separator="|" \
      --add-entry="Hostname (Nama Komputer, misal: $def_host)" \
      --add-entry="Username (Huruf kecil tanpa spasi, misal: farhan)" \
      --add-password="Password User & Root" \
      --add-password="Ulangi Password" \
      --add-entry="Timezone (Default: Asia/Jakarta)" \
      --width=520 --height=340) || exit 0

    IFS='|' read -r in_host in_user in_pw1 in_pw2 in_tz <<< "$form_out"
    in_host="${in_host:-$def_host}"
    in_tz="${in_tz:-Asia/Jakarta}"

    if [[ ! "$in_host" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
        zenity --error --text="Hostname hanya boleh huruf kecil, angka, dan tanda minus (-)."
        continue
    fi
    if [[ ! "$in_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ || "$in_user" == "root" ]]; then
        zenity --error --text="Username tidak valid! Gunakan huruf kecil (contoh: farhan) dan bukan 'root'."
        continue
    fi
    if [[ -z "$in_pw1" || "$in_pw1" != "$in_pw2" ]]; then
        zenity --error --text="Password kosong atau tidak sama! Silakan ulangi."
        continue
    fi
    if [[ ! -f "/usr/share/zoneinfo/$in_tz" ]]; then
        zenity --error --text="Timezone '$in_tz' tidak ditemukan (Contoh yang benar: Asia/Jakarta)."
        continue
    fi
    break
done

# 6. Konfirmasi Akhir
summary_text="<b>Ringkasan Konfigurasi Instalasi Arch Linux V3.1:</b>\n\n"
summary_text+="• <b>Profil Perangkat :</b> $hw_choice\n"
summary_text+="• <b>Desktop Pilihan  :</b> $de_choice\n"
if [[ "$INSTALL_MODE" == "auto" ]]; then
    summary_text+="• <b>Mode Partisi     :</b> Erase Disk Otomatis ($TARGET_DISK — Format $FS_TYPE)\n"
else
    summary_text+="• <b>Mode Partisi     :</b> Manual Partitioning (/mnt)\n"
fi
summary_text+="• <b>Hostname         :</b> $in_host\n"
summary_text+="• <b>Username (sudo)  :</b> $in_user\n"
summary_text+="• <b>Timezone         :</b> $in_tz\n\n"
summary_text+="Klik <b>Instal Sekarang</b> untuk menjalankan proses instalasi."

zenity --question \
  --title="Langkah 6/6 — Konfirmasi Instalasi" \
  --width=540 --height=340 \
  --ok-label="Instal Sekarang!" \
  --cancel-label="Batal" \
  --text="$summary_text" || exit 0

# Simpan konfigurasi dengan sudo ke /var/lib/arch-v3/gui-answers.env (Bebas Permission Denied!)
sudo mkdir -p /var/lib/arch-v3
sudo bash -c "cat > /var/lib/arch-v3/gui-answers.env" <<EOF
ARCH_V3_GUI_MODE=1
ARCH_V3_PROFILE='$hw_choice'
ARCH_V3_DESKTOP='$de_choice'
ARCH_V3_INSTALL_MODE='$INSTALL_MODE'
ARCH_V3_FS_TYPE='$FS_TYPE'
ARCH_V3_DISK='$TARGET_DISK'
ARCH_V3_HOSTNAME='$in_host'
ARCH_V3_USERNAME='$in_user'
ARCH_V3_USER_PW='$in_pw1'
ARCH_V3_TIMEZONE='$in_tz'
EOF
sudo chmod 600 /var/lib/arch-v3/gui-answers.env

# Jalankan installer di dalam jendela XFCE Terminal agar progres terlihat jelas secara real-time
exec xfce4-terminal --maximize --title="Arch Linux V3.1 Installer — Sedang Menginstal..." \
  -x bash -c "sudo /root/install-arch-live.sh --from-gui; echo ''; read -rp 'Tekan Enter untuk menutup jendela ini...'"
