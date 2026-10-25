#!/usr/bin/env bash
# ==============================================================================
# Membangun ISO Arch V3 Dual Edition (Live USB + installer).
# Dijalankan DI DALAM container archlinux:latest (lihat .github/workflows/build-iso.yml)
#   docker run --privileged --rm -v "$PWD":/workspace archlinux:latest bash /workspace/build-iso.sh
# ==============================================================================
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
PROFILE_DIR=/tmp/archiso-v3
WORK_DIR=/tmp/work
OUT_DIR="$WORKSPACE/out-iso"
AIROOTFS="$PROFILE_DIR/airootfs"

# Parameter kernel aman untuk NVMe & hybrid GPU saat Live Boot
LIVE_KPARAMS="nvme_core.default_ps_max_latency_us=0 intremap=nosid"

pacman -Syu --noconfirm archiso git
mkdir -p "$PROFILE_DIR" "$OUT_DIR"
cp -r /usr/share/archiso/configs/releng/* "$PROFILE_DIR"/

# --- Paket tambahan ----------------------------------------------------------
printf '\n' >> "$PROFILE_DIR/packages.x86_64"
cat >> "$PROFILE_DIR/packages.x86_64" <<'EOF'
git
wget
curl
dkms
linux-headers
linux-firmware
sof-firmware
alsa-ucm-conf
base-devel
networkmanager
iwd
pciutils
dmidecode
arch-install-scripts
gptfdisk
parted
dosfstools
e2fsprogs
btrfs-progs
reflector
terminus-font
# Desktop grafis Live USB: XFCE
xfce4
xfce4-goodies
xorg-server
xorg-xinit
lightdm
lightdm-gtk-greeter
network-manager-applet
sudo
# Calamares GUI installer and graphical desktop-choice dialog
calamares
zenity
polkit
polkit-gnome
EOF


# --- XFCE Live Desktop (akun liveuser dengan autologin LightDM) ----------------
mkdir -p "$AIROOTFS/etc/lightdm/lightdm.conf.d" "$AIROOTFS/etc/sudoers.d" "$AIROOTFS/usr/share/applications"
# Akun live dibuat saat customize_airootfs berjalan DI DALAM rootfs hasil pacstrap.
# Pada tahap ini airootfs masih overlay, sehingga /etc/passwd dan /etc/group belum ada.
CUSTOMIZE="$AIROOTFS/root/customize_airootfs.sh"
if [[ ! -f "$CUSTOMIZE" ]]; then
    cat > "$CUSTOMIZE" <<'CUSTOMIZE_EOF'
#!/usr/bin/env bash
set -e
CUSTOMIZE_EOF
fi
cat >> "$CUSTOMIZE" <<'CUSTOMIZE_EOF'

# Arch V3: siapkan akun live setelah paket terpasang di rootfs.
for group in wheel video audio storage input; do
    getent group "$group" >/dev/null 2>&1 || groupadd "$group"
done
if ! id liveuser >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio,storage,input -s /bin/bash liveuser
fi
CUSTOMIZE_EOF
chmod 755 "$CUSTOMIZE"
printf 'liveuser ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$AIROOTFS/etc/sudoers.d/90-liveuser"
chmod 440 "$AIROOTFS/etc/sudoers.d/90-liveuser"
cat > "$AIROOTFS/etc/lightdm/lightdm.conf.d/20-autologin.conf" <<'EOF'
[Seat:*]
autologin-user=liveuser
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOF
mkdir -p "$AIROOTFS/etc/systemd/system/graphical.target.wants"
ln -sf /usr/lib/systemd/system/lightdm.service "$AIROOTFS/etc/systemd/system/display-manager.service"
ln -sf /usr/lib/systemd/system/graphical.target "$AIROOTFS/etc/systemd/system/default.target"
cat > "$AIROOTFS/usr/share/applications/arch-v3-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install Arch Linux V3
Comment=Start the Arch Linux installer
Exec=/usr/local/bin/arch-v3-launch-installer
Icon=system-software-install
Terminal=false
Categories=System;
EOF

# --- Modul keyboard/trackpad agar langsung jalan di Live USB -----------------
# (applespi = keyboard/trackpad SPI MacBook A1708, acer_wmi = Acer Nitro)
HW_MODULES='MODULES+=(applespi intel_lpss_pci spi_pxa2xx_platform acer_wmi)'
if [[ -f "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf" ]]; then
    echo "$HW_MODULES" >> "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf"
else
    mkdir -p "$AIROOTFS/etc/mkinitcpio.conf.d"
    echo "$HW_MODULES" > "$AIROOTFS/etc/mkinitcpio.conf.d/10-hw-modules.conf"
fi

# --- Parameter kernel pada menu boot (GRUB, syslinux, systemd-boot) ----------
# Cocok untuk 'archisobasedir=arch' maupun placeholder 'archisobasedir=%INSTALL_DIR%'
for d in grub syslinux efiboot; do
    [[ -d "$PROFILE_DIR/$d" ]] || continue
    find "$PROFILE_DIR/$d" -type f \( -name '*.cfg' -o -name '*.conf' \) \
        -exec sed -i -E "s/(archisobasedir=[^ ]+)/\1 $LIVE_KPARAMS/g" {} +
done

# --- Installer Live USB ------------------------------------------------------
install -Dm755 "$WORKSPACE/install-arch-live.sh"   "$AIROOTFS/root/install-arch-live.sh"
install -Dm755 "$WORKSPACE/setup-arch-v3-dual.sh"  "$AIROOTFS/root/setup-arch-v3-dual.sh"
install -Dm755 "$WORKSPACE/arch-v3-welcome.sh"     "$AIROOTFS/usr/local/bin/arch-v3-welcome"
install -Dm755 "$WORKSPACE/scripts/arch-v3-launch-installer.sh" "$AIROOTFS/usr/local/bin/arch-v3-launch-installer"
install -Dm644 "$WORKSPACE/calamares/README.md" "$AIROOTFS/usr/share/doc/arch-v3/calamares-integration-status.md"
mkdir -p "$AIROOTFS/usr/local/bin"
ln -sf /root/install-arch-live.sh "$AIROOTFS/usr/local/bin/arch-v3-install"

# install -Dm755 di atas sudah menetapkan bit executable pada overlay; jangan edit
# profiledef.sh dengan sed multiline (itu yang sebelumnya memicu "unknown command: [").

# Tampilkan layar sambutan + tawaran installer di tty1 setelah autologin root
mkdir -p "$AIROOTFS/root"
cat >> "$AIROOTFS/root/.zlogin" <<'EOF'

# --- Arch V3 Live USB: tawarkan installer di tty1 ---
if [[ -z "${ARCH_V3_WELCOMED:-}" && "$(tty)" == "/dev/tty1" ]]; then
    export ARCH_V3_WELCOMED=1
    /usr/local/bin/arch-v3-welcome
fi
EOF

cat > "$AIROOTFS/etc/motd" <<'EOF'
Arch Linux V3 Live USB
Live desktop: XFCE   |   Installer grafis: ikon 'Install Arch Linux V3'   |   Wi-Fi: iwctl
EOF

# --- Bangun ISO --------------------------------------------------------------
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

# Checksum SHA-256 (dipakai make-live-usb.sh untuk verifikasi)
(cd "$OUT_DIR" && for f in *.iso; do sha256sum "$f" > "$f.sha256"; done)
ls -lh "$OUT_DIR"
