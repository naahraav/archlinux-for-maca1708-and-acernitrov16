#!/usr/bin/env bash
# ==============================================================================
# Arch Linux V3 Dual Edition - Installer untuk Live USB
# Target: Apple MacBook Pro A1708  &  Acer Nitro V 16 (Intel + NVIDIA)
#
# Jalankan dari Live USB:   arch-v3-install      (atau: ./install-arch-live.sh)
#
# Alur:
#   1. Deteksi hardware + cek UEFI + cek/sambungkan internet (Wi-Fi via iwctl)
#   2. Pilih disk (auto: hapus seluruh disk) atau mode manual (partisi sendiri)
#   3. Isi hostname, user, password, timezone
#   4. pacstrap + konfigurasi sistem + GRUB (UEFI, dengan fallback removable
#      agar muncul di Boot Manager MacBook lewat tombol Option)
#   5. (opsional) Pasang setup-arch-v3-dual.sh sebagai tugas first-boot:
#      KDE/Hyprland/GNOME/XFCE, driver NVIDIA, audio, kipas, dll.
# ==============================================================================
set -Eeuo pipefail

C_RED=$'\e[1;31m'; C_GRN=$'\e[1;32m'; C_YLW=$'\e[1;33m'; C_CYN=$'\e[1;36m'; C_RST=$'\e[0m'
info() { echo -e "${C_CYN}==>${C_RST} $*"; }
ok()   { echo -e "${C_GRN}[OK]${C_RST} $*"; }
warn() { echo -e "${C_YLW}[!]${C_RST} $*" >&2; }
die()  { echo -e "${C_RED}[GAGAL]${C_RST} $*" >&2; exit 1; }
trap 'die "Error di baris $LINENO (perintah: $BASH_COMMAND)"' ERR
trap 'echo; die "Dibatalkan oleh pengguna."' INT

# --- State -------------------------------------------------------------------
PROFILE="${ARCH_V3_PROFILE:-}"
INSTALL_MODE="auto"          # auto | manual
DISK=""; EFI_PART=""; ROOT_PART=""; EFI_DIR="/boot"
FS_TYPE="ext4"               # ext4 | btrfs
NEW_HOSTNAME=""; USERNAME=""; USER_PW=""; TIMEZONE="Asia/Jakarta"
RUN_SETUP="y"; UPDATE_MIRRORS="n"; DESKTOP="xfce"
WIFI_SSID=""; WIFI_PASS=""; LIVE_DISK=""
MAC_PARAMS="nvme_core.default_ps_max_latency_us=0 intremap=nosid mem_sleep_default=deep i915.enable_fbc=1 i915.enable_psr=1"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# --- Mode Otomatis dari GUI Zenity (--from-gui) ------------------------------
FROM_GUI=0
if [[ "${1:-}" == "--from-gui" && -f /var/lib/arch-v3/gui-answers.env ]]; then
    FROM_GUI=1
    # shellcheck disable=SC1091
    source /var/lib/arch-v3/gui-answers.env
    PROFILE="$ARCH_V3_PROFILE"
    DESKTOP="$ARCH_V3_DESKTOP"
    INSTALL_MODE="$ARCH_V3_INSTALL_MODE"
    FS_TYPE="$ARCH_V3_FS_TYPE"
    DISK="$ARCH_V3_DISK"
    NEW_HOSTNAME="$ARCH_V3_HOSTNAME"
    USERNAME="$ARCH_V3_USERNAME"
    USER_PW="$ARCH_V3_USER_PW"
    TIMEZONE="$ARCH_V3_TIMEZONE"
    RUN_SETUP="y"
    UPDATE_MIRRORS="n"
fi


# --- Helper input ------------------------------------------------------------
ask() {  # ask "Pertanyaan" "default"  -> stdout
    local prompt="$1" def="${2:-}" ans
    read -rp "$prompt${def:+ [$def]}: " ans
    echo "${ans:-$def}"
}
yesno() {  # yesno "Pertanyaan" y|n
    local def="${2:-y}" ans hint="Y/n"
    [[ $def == n ]] && hint="y/N"
    read -rp "$1 [$hint]: " ans
    ans="${ans:-$def}"
    [[ "${ans,,}" == y* ]]
}
ask_password() {  # hasil di REPLY_PW
    local p1 p2
    while true; do
        read -rsp "Password untuk $1: " p1; echo
        read -rsp "Ulangi password   : " p2; echo
        [[ -n $p1 && $p1 == "$p2" ]] && break
        warn "Password kosong atau tidak sama, coba lagi."
    done
    REPLY_PW="$p1"
}
part_name() {  # nvme0n1 -> nvme0n1p1 ; sda -> sda1
    if [[ $1 == *[0-9] ]]; then echo "${1}p${2}"; else echo "${1}${2}"; fi
}

# --- 1. Preflight, hardware, network -----------------------------------------
preflight() {
    [[ $EUID -eq 0 ]] || die "Jalankan sebagai root (di Live USB sudah otomatis root)."
    [[ -d /sys/firmware/efi/efivars ]] || die "Sistem tidak boot dalam mode UEFI. Boot USB lewat entri UEFI (MacBook: tahan Option -> pilih 'EFI Boot')."
    local c
    for c in lsblk sgdisk pacstrap genfstab arch-chroot mkfs.fat wipefs partprobe; do
        command -v "$c" &>/dev/null || die "Perintah '$c' tidak ditemukan."
    done
    if [[ ! -d /run/archiso ]]; then
        warn "Sepertinya ini bukan Live ISO Arch."
        yesno "Tetap lanjutkan?" n || exit 1
    fi
}

detect_profile() {
    local vendor product has_nvidia
    vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
    product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
    has_nvidia=$(lspci 2>/dev/null | grep -i nvidia || true)

    if [[ -z $PROFILE ]]; then
        if [[ $vendor == *Apple* || $product == *MacBookPro14,1* ]]; then
            PROFILE="macbook_a1708"
        elif [[ $vendor == *Acer* || -n $has_nvidia ]]; then
            PROFILE="acer_nitro_v16"
        fi
    fi

    if [[ -n $PROFILE ]]; then
        info "Hardware terdeteksi: $vendor $product -> profil: $PROFILE"
        yesno "Gunakan profil ini?" y && return 0
    fi
    echo "Pilih profil perangkat keras:"
    echo "  1) Apple MacBook Pro A1708"
    echo "  2) Acer Nitro V 16 (Intel + NVIDIA RTX)"
    case "$(ask 'Pilihan' 1)" in
        2) PROFILE="acer_nitro_v16" ;;
        *) PROFILE="macbook_a1708" ;;
    esac
}

have_net() {
    ping -c1 -W3 archlinux.org &>/dev/null || curl -fsI --max-time 5 https://archlinux.org &>/dev/null
}

wifi_connect() {
    command -v iwctl &>/dev/null || { warn "iwctl tidak tersedia."; return 1; }
    rfkill unblock wifi 2>/dev/null || true
    local dev
    dev=$(iwctl device list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/ station/{print $1; exit}')
    if [[ -z $dev ]]; then
        warn "Adapter Wi-Fi tidak terdeteksi. Gunakan kabel LAN / USB-C ethernet / USB tethering HP."
        return 1
    fi
    iwctl station "$dev" scan || true
    sleep 3
    iwctl station "$dev" get-networks || true
    WIFI_SSID=$(ask "Nama Wi-Fi (SSID)")
    read -rsp "Password Wi-Fi (kosongkan jika jaringan terbuka): " WIFI_PASS; echo
    if [[ -n $WIFI_PASS ]]; then
        iwctl --passphrase "$WIFI_PASS" station "$dev" connect "$WIFI_SSID" || { WIFI_SSID=""; WIFI_PASS=""; return 1; }
    else
        iwctl station "$dev" connect "$WIFI_SSID" || { WIFI_SSID=""; return 1; }
    fi
    local _
    for _ in $(seq 1 20); do
        have_net && return 0
        sleep 1
    done
    WIFI_SSID=""; WIFI_PASS=""
    return 1
}

ensure_network() {
    info "Memeriksa koneksi internet..."
    until have_net; do
        warn "Tidak ada koneksi internet (pacstrap butuh internet)."
        echo "  1) Sambungkan Wi-Fi"
        echo "  2) Cek ulang (setelah colok kabel LAN / USB tethering)"
        echo "  3) Batal"
        case "$(ask 'Pilihan' 1)" in
            1) wifi_connect || warn "Gagal menyambung Wi-Fi." ;;
            2) ;;
            3) die "Dibatalkan: tidak ada internet." ;;
        esac
    done
    ok "Internet tersambung."
    timedatectl set-ntp true 2>/dev/null || true
}

# --- 2. Disk -----------------------------------------------------------------
detect_live_disk() {
    local src pk
    src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
    [[ -n $src ]] || return 0
    pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)
    if [[ -n $pk ]]; then LIVE_DISK="/dev/$pk"; else LIVE_DISK="$src"; fi
}

list_disks() {
    local d
    while read -r d; do
        if [[ -n $LIVE_DISK && $d == "$LIVE_DISK" ]]; then continue; fi
        echo "$d"
    done < <(lsblk -dnpo NAME,TYPE -e 7,11 | awk '$2=="disk"{print $1}')
}

choose_disk() {
    local -a disks
    mapfile -t disks < <(list_disks)
    ((${#disks[@]} > 0)) || die "Tidak ada disk target. (Acer: jika NVMe tidak muncul, ubah mode Intel VMD/RST ke AHCI di BIOS.)"

    echo; info "Disk tujuan instalasi (Live USB sudah otomatis disembunyikan):"
    local i=1 d
    for d in "${disks[@]}"; do
        printf "  %d) %s\n" "$i" "$(lsblk -dnpo NAME,SIZE,TRAN,MODEL "$d" | tr -s ' ')"
        i=$((i + 1))
    done

    local n
    while true; do
        n=$(ask "Pilih nomor disk" 1)
        [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#disks[@]})) && break
        warn "Nomor tidak valid."
    done
    DISK="${disks[$((n - 1))]}"

    echo; lsblk -po NAME,SIZE,FSTYPE,LABEL,MODEL "$DISK"
    echo
    warn "SELURUH DATA di $DISK akan DIHAPUS PERMANEN."
    [[ "$(ask "Ketik HAPUS untuk melanjutkan")" == "HAPUS" ]] || die "Dibatalkan."
}

choose_install_mode() {
    echo
    info "Mode partisi:"
    echo "  1) Otomatis  - hapus seluruh disk: EFI 512MB + root (disarankan)"
    echo "  2) Manual    - partisi/mount sendiri (dual-boot, layout khusus)"
    case "$(ask 'Pilihan' 1)" in
        2) INSTALL_MODE="manual" ;;
        *) INSTALL_MODE="auto" ;;
    esac

    echo
    info "Filesystem root:"
    echo "  1) ext4  (sederhana, stabil)"
    echo "  2) btrfs (subvolume @ dan @home, kompresi zstd)"
    case "$(ask 'Pilihan' 1)" in
        2) FS_TYPE="btrfs" ;;
        *) FS_TYPE="ext4" ;;
    esac

    if [[ $INSTALL_MODE == "auto" ]]; then
        choose_disk
    fi
}

partition_auto() {
    info "Membuat tabel partisi GPT di $DISK ..."
    swapoff -a 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    wipefs -af "$DISK" >/dev/null
    sgdisk --zap-all "$DISK" >/dev/null
    sgdisk -n1:0:+512M -t1:ef00 -c1:"EFI System" "$DISK" >/dev/null
    sgdisk -n2:0:0   -t2:8300 -c2:"Arch Root"  "$DISK" >/dev/null
    partprobe "$DISK"; udevadm settle; sleep 1

    EFI_PART=$(part_name "$DISK" 1)
    ROOT_PART=$(part_name "$DISK" 2)
    [[ -b $EFI_PART && -b $ROOT_PART ]] || die "Partisi baru tidak terdeteksi ($EFI_PART / $ROOT_PART)."

    info "Memformat partisi ($FS_TYPE)..."
    mkfs.fat -F32 -n EFI "$EFI_PART" >/dev/null
    case "$FS_TYPE" in
        ext4)
            mkfs.ext4 -qF -L ArchRoot "$ROOT_PART"
            mount "$ROOT_PART" /mnt
            ;;
        btrfs)
            mkfs.btrfs -qf -L ArchRoot "$ROOT_PART"
            mount "$ROOT_PART" /mnt
            btrfs subvolume create /mnt/@ >/dev/null
            btrfs subvolume create /mnt/@home >/dev/null
            umount /mnt
            mount -o subvol=@,compress=zstd,noatime "$ROOT_PART" /mnt
            mount --mkdir -o subvol=@home,compress=zstd,noatime "$ROOT_PART" /mnt/home
            ;;
    esac
    mount --mkdir "$EFI_PART" /mnt/boot
    EFI_DIR="/boot"
    ok "Partisi siap: EFI=$EFI_PART  ROOT=$ROOT_PART"
}

partition_manual() {
    cat <<'EOF'

Mode MANUAL. Di shell berikut siapkan sendiri partisi lalu:
  - mount partisi root  ke /mnt
  - mount partisi EFI   ke /mnt/boot  (atau /mnt/boot/efi)
Contoh:
  cfdisk /dev/nvme0n1
  mkfs.ext4 /dev/nvme0n1p5 && mount /dev/nvme0n1p5 /mnt
  mount --mkdir /dev/nvme0n1p1 /mnt/boot
Ketik 'exit' bila selesai.
EOF
    while true; do
        bash -i || true
        if mountpoint -q /mnt && { mountpoint -q /mnt/boot || mountpoint -q /mnt/boot/efi; }; then
            break
        fi
        warn "/mnt dan /mnt/boot (atau /mnt/boot/efi) belum ter-mount."
        yesno "Buka shell lagi?" y || die "Dibatalkan."
    done
    if mountpoint -q /mnt/boot/efi; then EFI_DIR="/boot/efi"; else EFI_DIR="/boot"; fi
    ok "Memakai mount yang ada. Direktori EFI: $EFI_DIR"
}

# --- 3. Pertanyaan -----------------------------------------------------------
gather_info() {
    echo; info "Konfigurasi sistem"
    local def_host="arch-nitro"
    [[ $PROFILE == "macbook_a1708" ]] && def_host="arch-a1708"
    while true; do
        NEW_HOSTNAME=$(ask "Hostname" "$def_host")
        [[ $NEW_HOSTNAME =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] && break
        warn "Hostname hanya huruf kecil, angka, dan tanda minus."
    done
    while true; do
        USERNAME=$(ask "Nama user")
        [[ $USERNAME =~ ^[a-z_][a-z0-9_-]{0,31}$ && $USERNAME != "root" ]] && break
        warn "Nama user tidak valid (huruf kecil/angka/_/-, tidak boleh 'root')."
    done
    ask_password "$USERNAME (password root dibuat sama)"; USER_PW="$REPLY_PW"
    while true; do
        TIMEZONE=$(ask "Timezone" "$TIMEZONE")
        [[ -f /usr/share/zoneinfo/$TIMEZONE ]] && break
        warn "Timezone tidak ditemukan (contoh: Asia/Jakarta)."
    done
    echo
    echo "Setup V3 memasang SATU desktop environment pilihan Anda (Live USB sendiri memakai XFCE)."
    echo "Pilihan desktop untuk sistem Arch yang akan diinstal:"
    echo "  1) KDE Plasma"
    echo "  2) GNOME"
    echo "  3) XFCE"
    echo "  4) Hyprland"
    case "$(ask 'Desktop environment' '3')" in
        1) DESKTOP="kde" ;;
        2) DESKTOP="gnome" ;;
        4) DESKTOP="hyprland" ;;
        *) DESKTOP="xfce" ;;
    esac
    echo "Desktop yang dipilih: $DESKTOP"
    echo "Setup dijalankan otomatis saat boot pertama (butuh internet), lalu reboot sendiri."
    yesno "Jalankan setup V3 (desktop pilihan + driver/audio/perangkat) saat boot pertama?" y && RUN_SETUP="y" || RUN_SETUP="n"
    yesno "Perbarui daftar mirror dulu dengan reflector? (lebih cepat, tapi menambah waktu)" n && UPDATE_MIRRORS="y" || UPDATE_MIRRORS="n"
}

summary_and_confirm() {
    echo; echo "================ RINGKASAN ================"
    echo " Profil     : $PROFILE"
    if [[ $INSTALL_MODE == "auto" ]]; then
        echo " Disk       : $DISK  (DIHAPUS, GPT: EFI 512M + root $FS_TYPE)"
    else
        echo " Partisi    : manual (root /mnt, EFI $EFI_DIR)"
    fi
    echo " Hostname   : $NEW_HOSTNAME"
    echo " User       : $USERNAME (sudo)"
    echo " Timezone   : $TIMEZONE"
    echo " Desktop    : $DESKTOP"
    echo " Setup V3   : $([[ $RUN_SETUP == y ]] && echo 'ya, saat boot pertama' || echo 'tidak')"
    echo " Wi-Fi      : $([[ -n $WIFI_SSID ]] && echo "salin profil '$WIFI_SSID' ke sistem baru" || echo '-')"
    echo "==========================================="
    yesno "Mulai instalasi sekarang?" y || die "Dibatalkan."
}

# --- 4. Instalasi ------------------------------------------------------------
install_base() {
    if [[ $UPDATE_MIRRORS == "y" ]] && command -v reflector &>/dev/null; then
        info "Memperbarui mirror (reflector)..."
        reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist \
            || warn "reflector gagal, memakai mirrorlist bawaan."
    fi
    info "Menginstal sistem dasar (pacstrap)..."
    local -a pkgs=(
        base linux linux-headers linux-firmware intel-ucode
        base-devel sudo networkmanager iwd
        grub efibootmgr dosfstools e2fsprogs btrfs-progs
        git nano vim wget curl man-db bash-completion
        zram-generator pciutils dmidecode
    )
    pacstrap -K /mnt "${pkgs[@]}"
    genfstab -U /mnt > /mnt/etc/fstab
    ok "Sistem dasar terpasang."
}

configure_system() {
    info "Mengonfigurasi sistem..."
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/etc/localtime
    arch-chroot /mnt hwclock --systohc

    sed -i -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' -e 's/^#\(id_ID.UTF-8 UTF-8\)/\1/' /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen >/dev/null
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    echo "KEYMAP=us" > /mnt/etc/vconsole.conf
    echo "$NEW_HOSTNAME" > /mnt/etc/hostname
    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $NEW_HOSTNAME.localdomain $NEW_HOSTNAME
EOF

    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$USERNAME"
    printf '%s:%s\n' "$USERNAME" "$USER_PW" | arch-chroot /mnt chpasswd
    printf '%s:%s\n' "root" "$USER_PW" | arch-chroot /mnt chpasswd
    echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/10-wheel
    chmod 440 /mnt/etc/sudoers.d/10-wheel

    cat > /mnt/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF

    # MacBook A1708: keyboard/trackpad SPI harus ada di initramfs
    if [[ $PROFILE == "macbook_a1708" ]]; then
        sed -i 's/^MODULES=(/MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform /' /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P >/dev/null
    fi

    # Salin profil Wi-Fi yang dipakai saat instalasi (NetworkManager keyfile)
    if [[ -n $WIFI_SSID ]]; then
        local nm=/mnt/etc/NetworkManager/system-connections/installer-wifi.nmconnection
        mkdir -p "$(dirname "$nm")"
        {
            echo "[connection]"; echo "id=$WIFI_SSID"; echo "uuid=$(uuidgen)"
            echo "type=wifi"; echo "autoconnect=true"
            echo; echo "[wifi]"; echo "mode=infrastructure"; echo "ssid=$WIFI_SSID"
            if [[ -n $WIFI_PASS ]]; then
                echo; echo "[wifi-security]"; echo "key-mgmt=wpa-psk"; echo "psk=$WIFI_PASS"
            fi
            echo; echo "[ipv4]"; echo "method=auto"
            echo; echo "[ipv6]"; echo "method=auto"
        } > "$nm"
        chmod 600 "$nm"
    fi

    arch-chroot /mnt systemctl enable NetworkManager.service systemd-timesyncd.service fstrim.timer >/dev/null 2>&1
    ok "Sistem dikonfigurasi."
}

install_bootloader() {
    info "Memasang GRUB (UEFI)..."
    if [[ $PROFILE == "macbook_a1708" ]]; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"|&${MAC_PARAMS} |" /mnt/etc/default/grub
    fi
    # 1) Jalur fallback EFI/BOOT/BOOTX64.EFI -> muncul di boot menu MacBook (tombol Option)
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" --removable --recheck
    # 2) Entri NVRAM bernama (bisa gagal di Mac, tidak fatal)
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" --bootloader-id=ArchV3 --recheck \
        || warn "Entri NVRAM 'ArchV3' gagal dibuat; pakai entri fallback 'EFI Boot'."
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    ok "Bootloader terpasang."
}

setup_firstboot() {
    [[ $RUN_SETUP == "y" ]] || return 0
    local src="" c
    for c in "$SCRIPT_DIR/setup-arch-v3-dual.sh" /root/setup-arch-v3-dual.sh; do
        if [[ -f $c ]]; then src="$c"; break; fi
    done
    if [[ -z $src ]]; then
        warn "setup-arch-v3-dual.sh tidak ditemukan, setup first-boot dilewati."
        return 0
    fi
    info "Menjadwalkan setup lengkap V3 untuk boot pertama..."
    install -Dm755 "$src" /mnt/opt/arch-v3/setup-arch-v3-dual.sh
    mkdir -p /mnt/var/lib/arch-v3
    echo "$USERNAME" > /mnt/var/lib/arch-v3/user
    echo "$PROFILE"  > /mnt/var/lib/arch-v3/profile
    echo "$DESKTOP"  > /mnt/var/lib/arch-v3/desktop
    touch /mnt/var/lib/arch-v3/firstboot-pending

    cat > /mnt/usr/local/sbin/arch-v3-firstboot <<'EOF'
#!/usr/bin/env bash
# Dijalankan systemd saat boot pertama. Log: /var/log/arch-v3-firstboot.log
set -uo pipefail
USER_NAME=$(cat /var/lib/arch-v3/user)
PROFILE=$(cat /var/lib/arch-v3/profile)
DESKTOP=$(cat /var/lib/arch-v3/desktop 2>/dev/null || echo xfce)
LOG=/var/log/arch-v3-firstboot.log
SUDOERS=/etc/sudoers.d/99-arch-v3-firstboot
trap 'rm -f "$SUDOERS"' EXIT

echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS"
chmod 440 "$SUDOERS"

for _ in $(seq 1 30); do
    ping -c1 -W2 archlinux.org &>/dev/null && break
    sleep 2
done

runuser -l "$USER_NAME" -c "export ARCH_V3_PROFILE='$PROFILE' ARCH_V3_DESKTOP='$DESKTOP'; bash /opt/arch-v3/setup-arch-v3-dual.sh" 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}

if [[ $rc -eq 0 ]]; then
    rm -f /var/lib/arch-v3/firstboot-pending
    systemctl disable arch-v3-firstboot.service
    wall "Arch V3: setup selesai. Sistem reboot dalam 15 detik..."
    sleep 15
    systemctl reboot --no-block
else
    wall "Arch V3: setup GAGAL (kode $rc). Lihat $LOG. Akan dicoba lagi saat boot berikutnya, atau jalankan: sudo systemctl start arch-v3-firstboot"
fi
exit $rc
EOF
    chmod 755 /mnt/usr/local/sbin/arch-v3-firstboot

    cat > /mnt/etc/systemd/system/arch-v3-firstboot.service <<'EOF'
[Unit]
Description=Arch V3 first-boot setup (desktop, driver, tweak perangkat)
ConditionPathExists=/var/lib/arch-v3/firstboot-pending
Wants=network-online.target
After=network-online.target NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/arch-v3-firstboot
TimeoutStartSec=infinity
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
    arch-chroot /mnt systemctl enable arch-v3-firstboot.service >/dev/null 2>&1
    ok "Setup first-boot dijadwalkan."
}

finish() {
    sync
    umount -R /mnt 2>/dev/null || warn "Gagal unmount otomatis; lakukan: umount -R /mnt"
    echo
    echo "=============================================================================="
    ok "INSTALASI SELESAI"
    echo " 1. Cabut Live USB saat komputer restart."
    [[ $PROFILE == "macbook_a1708" ]] && echo " 2. MacBook: bila tidak langsung boot, tahan Option saat menyala -> pilih 'EFI Boot'."
    if [[ $RUN_SETUP == "y" ]]; then
        echo " -> Boot pertama akan memasang desktop pilihan ($DESKTOP) dan setup perangkat otomatis (login di TTY"
        echo "    lalu pantau: journalctl -fu arch-v3-firstboot). Sistem reboot sendiri jika sukses."
    else
        echo " -> Setup lengkap bisa dijalankan manual: bash /root/setup-arch-v3-dual.sh (di sistem baru)"
    fi
    echo "=============================================================================="
    if yesno "Reboot sekarang?" y; then systemctl reboot; fi
}

# --- Main --------------------------------------------------------------------
main() {
    clear 2>/dev/null || true
    echo "=============================================================================="
    echo "  ARCH LINUX V3.1 - INSTALLER LIVE USB (MacBook Pro A1708 & Acer Nitro V 16)"
    echo "=============================================================================="
    preflight
    if (( FROM_GUI == 1 )); then
        info "Menjalankan konfigurasi dari GUI Wizard..."
        ensure_network
        detect_live_disk
    else
        detect_profile
        ensure_network
        detect_live_disk
        choose_install_mode
        gather_info
        summary_and_confirm
    fi

    if [[ $INSTALL_MODE == "auto" ]]; then partition_auto; else partition_manual; fi
    install_base
    configure_system
    install_bootloader
    setup_firstboot
    rm -f /var/lib/arch-v3/gui-answers.env
    finish
}
main "$@"
