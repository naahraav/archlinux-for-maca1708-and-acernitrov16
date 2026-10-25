#!/usr/bin/env bash
# ==============================================================================
# Membangun ISO Arch V3.1 Dual Edition (Live USB XFCE + GUI Installer).
# Dijalankan DI DALAM container archlinux:latest
# ==============================================================================
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
PROFILE_DIR=/tmp/archiso-v3
WORK_DIR=/tmp/work
OUT_DIR="$WORKSPACE/out-iso"
AIROOTFS="$PROFILE_DIR/airootfs"

# Parameter kernel aman untuk NVMe & hybrid GPU saat Live Boot
LIVE_KPARAMS="nvme_core.default_ps_max_latency_us=0 intremap=nosid"

pacman -Syu --noconfirm archiso git base-devel sudo

rm -rf "$PROFILE_DIR" "$WORK_DIR"
mkdir -p "$PROFILE_DIR" "$OUT_DIR"
cp -r /usr/share/archiso/configs/releng/* "$PROFILE_DIR"/

# --- Paket tambahan (100% repositori resmi Arch, bebas gagal build AUR) ------
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
network-manager-applet
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
# Desktop grafis Live USB: XFCE core packages
exo
garcon
thunar
thunar-volman
tumbler
xfce4-appfinder
xfce4-panel
xfce4-power-manager
xfce4-session
xfce4-settings
xfce4-terminal
xfconf
xfdesktop
xfwm4
mousepad
xfce4-notifyd
xfce4-screensaver
xfce4-screenshooter
xfce4-taskmanager
xfce4-whiskermenu-plugin
xorg-server
xorg-xinit
lightdm
lightdm-gtk-greeter
sudo
zenity
polkit
polkit-gnome
gparted
EOF

# --- XFCE Live Desktop (akun liveuser dengan autologin LightDM) --------------
mkdir -p "$AIROOTFS/etc/lightdm/lightdm.conf.d" \
         "$AIROOTFS/etc/sudoers.d" \
         "$AIROOTFS/usr/share/applications" \
         "$AIROOTFS/etc/xdg/autostart"

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
ln -sf /usr/lib/systemd/system/NetworkManager.service "$AIROOTFS/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# Desktop Entry untuk Menu Aplikasi, Layar Desktop XFCE, dan Autostart
cat > "$AIROOTFS/usr/share/applications/arch-v3-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install Arch Linux V3
Comment=Instal Arch Linux V3 (Pilih Desktop Environment & Disk)
Exec=/usr/local/bin/arch-v3-launch-installer
Icon=system-software-install
Terminal=false
Categories=System;
StartupNotify=true
EOF

# Autostart saat masuk desktop XFCE agar langsung menyapa pengguna
cat > "$AIROOTFS/etc/xdg/autostart/arch-v3-welcome-gui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Arch Linux V3 Welcome & Installer
Comment=Mulai instalasi Arch Linux V3
Exec=/usr/local/bin/arch-v3-launch-installer
Icon=system-software-install
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# Buat akun liveuser & pasang ikon di Desktop dalam customize_airootfs.sh
CUSTOMIZE="$AIROOTFS/root/customize_airootfs.sh"
if [[ ! -f "$CUSTOMIZE" ]]; then
    cat > "$CUSTOMIZE" <<'CUSTOMIZE_EOF'
#!/usr/bin/env bash
set -e
CUSTOMIZE_EOF
fi
cat >> "$CUSTOMIZE" <<'CUSTOMIZE_EOF'

# Arch V3.1: siapkan akun liveuser & ikon desktop setelah paket terpasang
for group in wheel video audio storage input network; do
    getent group "$group" >/dev/null 2>&1 || groupadd "$group"
done
if ! id liveuser >/dev/null 2>&1; then
    useradd -m -G wheel,video,audio,storage,input,network -s /bin/bash liveuser
    passwd -d liveuser >/dev/null 2>&1 || true
fi
install -dm755 -o liveuser -g liveuser /home/liveuser/Desktop
install -Dm755 -o liveuser -g liveuser /usr/share/applications/arch-v3-install.desktop /home/liveuser/Desktop/arch-v3-install.desktop
CUSTOMIZE_EOF
chmod 755 "$CUSTOMIZE"

# --- Modul keyboard/trackpad agar langsung jalan di Live USB -----------------
HW_MODULES='MODULES+=(applespi intel_lpss_pci spi_pxa2xx_platform acer_wmi)'
if [[ -f "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf" ]]; then
    echo "$HW_MODULES" >> "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf"
else
    mkdir -p "$AIROOTFS/etc/mkinitcpio.conf.d"
    echo "$HW_MODULES" > "$AIROOTFS/etc/mkinitcpio.conf.d/10-hw-modules.conf"
fi

# --- Parameter kernel pada menu boot (GRUB, syslinux, systemd-boot) ----------
for d in grub syslinux efiboot; do
    [[ -d "$PROFILE_DIR/$d" ]] || continue
    find "$PROFILE_DIR/$d" -type f \( -name '*.cfg' -o -name '*.conf' \) \
        -exec sed -i -E "s/(archisobasedir=[^ ]+)/\1 $LIVE_KPARAMS/g" {} +
done

# --- Salin semua script installer ke Live ISO --------------------------------
install -Dm755 "$WORKSPACE/install-arch-live.sh"              "$AIROOTFS/root/install-arch-live.sh"
install -Dm755 "$WORKSPACE/setup-arch-v3-dual.sh"             "$AIROOTFS/root/setup-arch-v3-dual.sh"
install -Dm755 "$WORKSPACE/arch-v3-welcome.sh"                "$AIROOTFS/usr/local/bin/arch-v3-welcome"
install -Dm755 "$WORKSPACE/scripts/arch-v3-launch-installer.sh" "$AIROOTFS/usr/local/bin/arch-v3-launch-installer"
mkdir -p "$AIROOTFS/usr/local/bin"
ln -sf /root/install-arch-live.sh "$AIROOTFS/usr/local/bin/arch-v3-install"

cat > "$AIROOTFS/etc/motd" <<'EOF'
Arch Linux V3.1 Live USB
Live desktop: XFCE | GUI Installer: Klik 'Install Arch Linux V3' di Desktop | CLI: sudo arch-v3-install
EOF

# --- Bangun ISO --------------------------------------------------------------
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

# Checksum SHA-256
(cd "$OUT_DIR" && for f in *.iso; do sha256sum "$f" > "$f.sha256"; done)
ls -lh "$OUT_DIR"
