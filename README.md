# Arch Linux Custom V3.1 - Full Fixed GUI Edition (MacBook Pro A1708 & Acer Nitro V 16)

Versi **V3.1 Fixed** ini memperbaiki seluruh 6 masalah pada file sebelumnya:
1. **Struktur Folder Langsung di Root (`.github/workflows/build-iso.yml`):** Siap langsung di-upload ke GitHub dan bahkan dilengkapi auto-fix jika tidak sengaja ter-upload di dalam subfolder `archv3/`.
2. **Bebas Gagal Build AUR Calamares:** Menghapus ketergantungan `calamares` AUR yang kosong dan sering gagal kompilasi di container CI, digantikan dengan **GUI Installer Wizard berbasis Zenity + GParted + Live Engine** yang 100% memakai paket resmi Arch Linux.
3. **Bebas Error `Permission Denied`:** Penyimpanan konfigurasi GUI ke `/var/lib/arch-v3` kini menggunakan `sudo` dengan benar.
4. **GUI Installer Terhubung Langsung ke Mesin Partisi & Instalasi:**
   Saat boot ke Live USB (Desktop XFCE), jendela GUI otomatis muncul (dan tersedia ikon **Install Arch Linux V3** di layar Desktop) untuk memilih:
   - **Profil Laptop:** Apple MacBook Pro A1708 atau Acer Nitro V 16 (Intel + NVIDIA RTX).
   - **Desktop Environment (Pilih 1 seperti CachyOS):** KDE Plasma 6, Hyprland, GNOME, atau XFCE4.
   - **Mode Partisi:** *Erase Disk Otomatis* (EXT4 / BTRFS) atau *Manual Partitioning* (dengan tombol buka aplikasi grafis **GParted** untuk Dual-Boot).
   - **Akun Pengguna:** Hostname, Username (`sudo`), Password, dan Timezone.
