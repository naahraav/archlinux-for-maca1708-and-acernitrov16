#!/usr/bin/env bash
# ==============================================================================
# Custom Arch Linux ULTIMATE V3 - Dual Hardware Edition
# Target 1: Apple MacBook Pro A1708 (2016/2017)
# Target 2: Acer Nitro V 16 (Intel CPU + NVIDIA RTX Hybrid/Optimus)
# DE: satu pilihan: KDE Plasma, Hyprland, GNOME, atau XFCE
# ==============================================================================

set -e

echo "=============================================================================="
echo "   ARCH LINUX CUSTOM OS BUILDER V3 (MACBOOK PRO A1708 & ACER NITRO V 16)      "
echo "=============================================================================="

# Deteksi Otomatis Hardware via DMI & PCI
SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
HAS_NVIDIA=$(lspci | grep -i "nvidia" || true)

# Fungsi aman untuk menambah parameter kernel (GRUB / systemd-boot), idempoten
add_kernel_params() {
    local params="$1" esc
    esc=$(printf '%s' "$params" | sed -e 's/[\\&|]/\\&/g')
    if [ -f /etc/default/grub ]; then
        if ! grep -qF -- "$params" /etc/default/grub; then
            sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"|&${esc} |" /etc/default/grub
        fi
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    elif [ -d /boot/loader/entries ]; then
        for entry in /boot/loader/entries/*.conf; do
            if ! grep -qF -- "$params" "$entry"; then
                sudo sed -i "/^options/ s|\$| ${esc}|" "$entry"
            fi
        done
    fi
}

DESKTOP="${ARCH_V3_DESKTOP:-}"
if [[ -z "$DESKTOP" ]]; then
    echo "Pilih SATU Desktop Environment untuk sistem ini:"
    echo "1) KDE Plasma"
    echo "2) GNOME"
    echo "3) XFCE (default)"
    echo "4) Hyprland"
    read -rp "Pilihan [1-4, default 3]: " de_choice
    case "$de_choice" in
        1) DESKTOP="kde" ;;
        2) DESKTOP="gnome" ;;
        4) DESKTOP="hyprland" ;;
        *) DESKTOP="xfce" ;;
    esac
fi
case "$DESKTOP" in kde|gnome|xfce|hyprland) ;; *) echo "Pilihan desktop tidak valid: $DESKTOP" >&2; exit 1 ;; esac
echo "-> Desktop Environment yang akan dipasang: $DESKTOP"

DETECTED_PROFILE=""
if [[ -n "${ARCH_V3_PROFILE:-}" ]]; then
    # Dioper oleh installer Live USB (install-arch-live.sh / service first-boot)
    DETECTED_PROFILE="$ARCH_V3_PROFILE"
    echo "-> Profil dari installer Live USB: $DETECTED_PROFILE"
elif [[ "$SYS_VENDOR" == *"Apple"* ]] || [[ "$PRODUCT_NAME" == *"MacBookPro14,1"* ]]; then
    DETECTED_PROFILE="macbook_a1708"
    echo "-> Hardware Terdeteksi Otomatis: Apple MacBook Pro A1708 ($PRODUCT_NAME)"
elif [[ "$SYS_VENDOR" == *"Acer"* ]] || [[ -n "$HAS_NVIDIA" ]]; then
    DETECTED_PROFILE="acer_nitro_v16"
    echo "-> Hardware Terdeteksi Otomatis: Acer Nitro V 16 Intel + NVIDIA ($PRODUCT_NAME)"
else
    echo "Pilih profil perangkat keras yang ingin dioptimalkan:"
    echo "1) Apple MacBook Pro A1708 (8GB RAM)"
    echo "2) Acer Nitro V 16 (Intel + NVIDIA RTX)"
    read -rp "Masukkan pilihan [1/2] (Default: 1): " choice
    if [[ "$choice" == "2" ]]; then
        DETECTED_PROFILE="acer_nitro_v16"
    else
        DETECTED_PROFILE="macbook_a1708"
    fi
fi

echo "[1/10] Mengaktifkan repositori Multilib (Wajib untuk NVIDIA 32-bit & Steam/Gaming)..."
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    sudo sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
fi

echo "[2/10] Memperbarui sistem & menginstal paket inti, Audio PipeWire, dan Firmware..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git wget curl dkms linux-headers \
    linux-firmware sof-firmware alsa-ucm-conf alsa-utils \
    intel-ucode intel-media-driver libva-intel-driver vulkan-intel \
    networkmanager iwd bluez bluez-utils wireless-regdb \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    easyeffects lsp-plugins calf dolphin \
    thermald acpi_call zram-generator brightnessctl playerctl \
    libinput xf86-input-libinput

echo "[3/10] Mengonfigurasi ZRAM (Kompresi zstd Cepat)..."
sudo bash -c 'cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF'
sudo systemctl daemon-reload
sudo systemctl start /dev/zram0 || true

echo "[4/10] Menginstal SATU Desktop Environment ($DESKTOP) dan display manager..."
sudo pacman -S --needed --noconfirm sddm
case "$DESKTOP" in
    kde)
        sudo pacman -S --needed --noconfirm plasma-meta konsole dolphin ark
        ;;
    gnome)
        sudo pacman -S --needed --noconfirm gnome gnome-tweaks
        ;;
    xfce)
        sudo pacman -S --needed --noconfirm xfce4 xfce4-goodies xorg-server xorg-xinit
        ;;
    hyprland)
        sudo pacman -S --needed --noconfirm hyprland waybar wofi kitty dunst grim slurp \
            xdg-desktop-portal-hyprland polkit-kde-agent qt5-wayland qt6-wayland dolphin
        ;;
esac
sudo systemctl enable sddm.service --force
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now thermald

echo "[5/10] Menginstal YAY (AUR Helper)..."
if ! command -v yay &> /dev/null; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
    rm -rf /tmp/yay
fi

# ==============================================================================
# CABANG 1: OPTIMASI KHUSUS APPLE MACBOOK PRO A1708
# ==============================================================================
if [[ "$DETECTED_PROFILE" == "macbook_a1708" ]]; then
    echo ">>> MENJALANKAN OPTIMASI ULTIMATE UNTUK MACBOOK PRO A1708 <<<"

    echo "[6/10] Menyuntikkan Modul Apple SPI (Keyboard & Trackpad A1708)..."
    if ! grep -q "applespi" /etc/mkinitcpio.conf; then
        sudo sed -i 's/^MODULES=(/MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform /' /etc/mkinitcpio.conf
        sudo mkinitcpio -P
    fi

    echo "[7/10] Mengatur Parameter Kernel NVMe, Sleep & Power Saving Intel Iris..."
    KERNEL_PARAMS="nvme_core.default_ps_max_latency_us=0 intremap=nosid mem_sleep_default=deep i915.enable_fbc=1 i915.enable_psr=1"
    add_kernel_params "$KERNEL_PARAMS"

    sudo mkdir -p /etc/NetworkManager/conf.d
    sudo bash -c 'cat > /etc/NetworkManager/conf.d/wifi_backend.conf <<EOF
[device]
wifi.backend=iwd
wifi.powersave=2
EOF'

    echo "[8/10] Memasang Systemd Sleep Hook, Fan Control (mbpfan), & Kalibrasi Kamera FaceTimeHD..."
    sudo bash -c 'cat > /usr/lib/systemd/system-sleep/a1708-sleep-fix.sh << "EOF"
#!/bin/sh
case "$1" in
    pre)
        systemctl stop iwd || true
        modprobe -r brcmfmac_wcc brcmfmac brcmutil || true
        ;;
    post)
        modprobe brcmfmac || true
        systemctl start iwd || true
        ;;
esac
EOF'
    sudo chmod +x /usr/lib/systemd/system-sleep/a1708-sleep-fix.sh

    yay -S --needed --noconfirm mbpfan-git auto-cpufreq facetimehd-firmware bcwc-pcie-git
    sudo systemctl enable --now mbpfan
    sudo systemctl enable --now auto-cpufreq

    for dat_file in 1771_01XX.dat 1871_01XX.dat 1874_01XX.dat 1901_01XX.dat; do
        sudo wget -q "https://raw.githubusercontent.com/patjak/facetimehd-firmware/master/$dat_file" -O "/lib/firmware/facetimehd/$dat_file" || true
    done
    sudo modprobe -r facetimehd 2>/dev/null || true
    sudo modprobe facetimehd 2>/dev/null || true

    echo "[9/10] Mengompilasi Driver Audio CS8409 + Pacman Auto-Rebuild Hook..."
    sudo mkdir -p /opt/a1708-audio
    sudo rm -rf /opt/a1708-audio/*
    sudo git clone https://github.com/davidjo/snd_hda_macbookpro.git /opt/a1708-audio
    (cd /opt/a1708-audio && sudo ./install.cirrus.driver.sh)

    sudo mkdir -p /etc/pacman.d/hooks
    sudo bash -c 'cat > /etc/pacman.d/hooks/99-a1708-audio.hook <<EOF
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen

[Action]
Description = Memperbarui Driver Audio Cirrus Logic CS8409 MacBook Pro A1708...
When = PostTransaction
Exec = /bin/sh -c "cd /opt/a1708-audio && ./install.cirrus.driver.sh"
EOF'

    echo "[10/10] Menulis Konfigurasi Hyprland Retina (2560x1600 @ 1.5x)..."
    mkdir -p ~/.config/hypr
    cat > ~/.config/hypr/hyprland.conf <<EOF
monitor=eDP-1,2560x1600@60,0x0,1.5
exec-once = waybar & dunst & easyeffects --gapplication-service & /usr/lib/polkit-kde-authentication-agent-1
input {
    kb_layout = us
    touchpad {
        natural_scroll = yes
        tap-to-click = yes
        clickfinger_behavior = yes
    }
}
gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
}
\$mainMod = SUPER
bind = \$mainMod, RETURN, exec, kitty
bind = \$mainMod, Q, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, dolphin
bind = \$mainMod, D, exec, wofi --show drun
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
bind = , XF86KbdBrightnessUp, exec, brightnessctl -d '*::kbd_backlight' set +10%
bind = , XF86KbdBrightnessDown, exec, brightnessctl -d '*::kbd_backlight' set 10%-
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
EOF

# ==============================================================================
# CABANG 2: OPTIMASI KHUSUS ACER NITRO V 16 (INTEL + NVIDIA RTX)
# ==============================================================================
elif [[ "$DETECTED_PROFILE" == "acer_nitro_v16" ]]; then
    echo ">>> MENJALANKAN OPTIMASI ULTIMATE UNTUK ACER NITRO V 16 (INTEL + NVIDIA) <<<"

    echo "[6/10] Menginstal Driver NVIDIA DKMS, Hybrid Optimus (PRIME), & Vulkan Gaming Stack..."
    sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils \
        nvidia-settings nvidia-prime libva-nvidia-driver opencl-nvidia \
        vulkan-icd-loader lib32-vulkan-icd-loader lib32-vulkan-intel \
        gamemode lib32-gamemode mangohud lib32-mangohud power-profiles-daemon

    echo "[7/10] Mengonfigurasi Early KMS NVIDIA, VRAM Sleep Preservation, & Dynamic Boost..."
    # Menyuntikkan modul i915 & NVIDIA ke mkinitcpio
    if ! grep -q "nvidia_drm" /etc/mkinitcpio.conf; then
        sudo sed -i 's/^MODULES=(/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm acer_wmi /' /etc/mkinitcpio.conf
    fi

    # Konfigurasi modprobe agar Wayland/Hyprland tidak crash saat sleep/wake di GPU NVIDIA
    sudo bash -c 'cat > /etc/modprobe.d/nvidia-nitro.conf <<EOF
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_DynamicPowerManagement=0x02
EOF'
    sudo mkinitcpio -P

    # Parameter Kernel untuk Intel + NVIDIA Hybrid & WMI Acer Nitro
    NITRO_PARAMS="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 acpi_osi=! acpi_osi='Windows 2022' pcie_aspm=force"
    add_kernel_params "$NITRO_PARAMS"

    # Aktifkan layanan NVIDIA Dynamic Boost (nvidia-powerd) & Sleep Services
    sudo systemctl enable --now nvidia-powerd.service || true
    sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
    sudo systemctl enable --now power-profiles-daemon

    echo "[8/10] Menginstal Pengontrol GPU (EnvyControl) & Kontrol Kipas/NitroSense Linux..."
    yay -S --needed --noconfirm envycontrol nbfc-linux

    # Pacman Hook untuk rebuild initramfs otomatis saat driver NVIDIA atau Kernel di-update
    sudo mkdir -p /etc/pacman.d/hooks
    sudo bash -c 'cat > /etc/pacman.d/hooks/99-nvidia-nitro.hook <<EOF
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia-dkms
Target=linux
Target=linux-lts
Target=linux-zen

[Action]
Description=Memperbarui Initramfs untuk Driver NVIDIA Acer Nitro V 16...
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c "while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P"
EOF'

    echo "[9/10] Mengoptimalkan Audio Intel SOF (Speaker & Dual-Mic Array Acer Nitro V 16)..."
    sudo bash -c 'cat > /etc/modprobe.d/sof-audio-nitro.conf <<EOF
options snd-intel-dspcfg dsp_driver=3
EOF'

    echo "[10/10] Menulis Konfigurasi Hyprland Khusus Acer Nitro V 16 (High Refresh Rate 165Hz+ & NVIDIA Wayland)..."
    mkdir -p ~/.config/hypr
    cat > ~/.config/hypr/hyprland.conf <<EOF
# Otomatis menggunakan resolusi & refresh rate tertinggi (165Hz / 180Hz) pada layar 16:10 Nitro V 16
monitor=,highrr,auto,1.25

# Variabel Lingkungan Wajib untuk Hyprland pada Hybrid Intel + NVIDIA
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct

cursor {
    no_hardware_cursors = true
}

exec-once = waybar & dunst & easyeffects --gapplication-service & /usr/lib/polkit-kde-authentication-agent-1

input {
    kb_layout = us
    touchpad {
        natural_scroll = yes
        tap-to-click = yes
    }
}

gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
}

\$mainMod = SUPER
bind = \$mainMod, RETURN, exec, kitty
bind = \$mainMod, Q, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, dolphin
bind = \$mainMod, D, exec, wofi --show drun
# Shortcut jalankan aplikasi dengan GPU Diskrit NVIDIA (PRIME Render Offload)
bind = \$mainMod SHIFT, RETURN, exec, prime-run kitty
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
bind = , XF86KbdBrightnessUp, exec, brightnessctl -d '*::kbd_backlight' set +10%
bind = , XF86KbdBrightnessDown, exec, brightnessctl -d '*::kbd_backlight' set 10%-
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
EOF
fi

# Profil DSP Audio Universal (Bass Enhancer & Limiter)
mkdir -p ~/.config/easyeffects/output
cat > ~/.config/easyeffects/output/Custom_Laptop_DSP.json <<EOF
{
    "output": {
        "bass_enhancer#0": {
            "amount": 6.5,
            "blend": 0.0,
            "Bypass": false,
            "floor": 65.0,
            "floor-active": true,
            "harmonics": 8.5,
            "input-gain": 0.0,
            "output-gain": 0.0,
            "scope": 100.0
        },
        "equalizer#0": {
            "balance": 0.0,
            "Bypass": false,
            "input-gain": 0.0,
            "mode": "IIR",
            "num-bands": 5,
            "output-gain": 0.0,
            "split-channels": false
        },
        "limiter#0": {
            "alr": false,
            "attack": 5.0,
            "Bypass": false,
            "dithering": "None",
            "gain-boost": true,
            "input-gain": 2.0,
            "lookahead": 5.0,
            "mode": "Herm Thin",
            "output-gain": -0.5,
            "oversampling": "None",
            "release": 50.0,
            "sidechain-preamp": 0.0,
            "stereo-link": 100.0,
            "threshold": -1.0
        },
        "plugins_order": [
            "bass_enhancer#0",
            "equalizer#0",
            "limiter#0"
        ]
    }
}
EOF

echo "=============================================================================="
echo "INSTALASI V3 SELESAI UNTUK PROFIL: $DETECTED_PROFILE"
echo "Desktop yang terpasang: $DESKTOP. Login melalui SDDM setelah reboot."
echo "=============================================================================="
