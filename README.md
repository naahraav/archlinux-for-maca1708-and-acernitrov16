# Arch Linux Custom V3 - Dual Laptop Edition (MacBook Pro A1708 & Acer Nitro V 16 Intel+NVIDIA)

> **Baru: Live USB XFCE + installer interaktif.** Saat instalasi Anda memilih satu desktop untuk sistem terpasang (KDE Plasma, GNOME, XFCE, atau Hyprland); hanya pilihan itu yang dipasang. ISO bisa langsung di-boot dari flashdisk dan memandu instalasi dari nol (partisi, sistem dasar, bootloader, user), lalu menjalankan setup V3 otomatis saat boot pertama. Lihat bagian [Live USB & Instalasi](#live-usb--instalasi).

Paket **V3 Dual-Edition** ini dirancang cerdas dengan fitur **Auto-Hardware Detection**. Satu file `.iso` dan satu script installer (`setup-arch-v3-dual.sh`) dapat digunakan di **dua laptop berbeda** tanpa bentrok driver:
- **Apple MacBook Pro A1708 (2016/2017)**
- **Acer Nitro V 16 (Intel Core/Ultra + NVIDIA GeForce RTX)**

## Fitur Khusus yang Ditambahkan untuk Acer Nitro V 16 (Intel + NVIDIA):
1. **Hybrid Graphics (NVIDIA Optimus / PRIME + Wayland Fix):**
   - Menginstal `nvidia-dkms`, `nvidia-utils`, `lib32-nvidia-utils`, `nvidia-prime`, dan `libva-nvidia-driver`.
   - Mengaktifkan `nvidia_drm.modeset=1` dan `nvidia_drm.fbdev=1` serta `NVreg_PreserveVideoMemoryAllocations=1` agar **Hyprland, KDE Plasma, dan GNOME (Wayland)** berjalan mulus di layar 165Hz/180Hz tanpa blank/crash setelah *sleep*.
2. **Switch Mode GPU Mudah (`EnvyControl`):**
   - Bisa berpindah mode kartu grafis kapan saja lewat terminal:
     - `sudo envycontrol -s hybrid` (Hemat baterai + performa otomatis dengan `prime-run`)
     - `sudo envycontrol -s nvidia` (Performa rata kanan khusus gaming)
     - `sudo envycontrol -s integrated` (Hanya GPU Intel untuk hemat baterai maksimal saat kuliah/bepergian)
3. **NVIDIA Dynamic Boost (`nvidia-powerd`) & Gaming Stack:**
   - Mengaktifkan fitur *Dynamic Boost* resmi NVIDIA agar alokasi watt antara CPU Intel dan GPU RTX diatur otomatis saat bermain game, lengkap dengan `gamemode`, `mangohud`, dan repositori `multilib` (32-bit).
4. **Audio Intel SOF (`sof-firmware` + `alsa-ucm-conf`):**
   - Wajib untuk laptop Intel generasi baru seperti Acer Nitro V 16 agar speaker internal dan *dual-array microphone* langsung terdeteksi.
5. **Kontrol Kipas & Termal Acer (`acer_wmi` + `nbfc-linux` + `power-profiles-daemon`):**
   - Mengaktifkan modul kernel `acer_wmi` dengan parameter Windows 2022 ACPI untuk manajemen kipas, tombol fungsi, dan lampu *backlight* keyboard.

## Live USB & Instalasi

### 1. Tulis ISO ke flashdisk (min. 4 GB)
| Sistem | Cara |
|---|---|
| Linux / macOS | `sudo ./make-live-usb.sh` (cari ISO otomatis, pilih USB, verifikasi checksum & hasil tulis) |
| Windows | Rufus (pilih mode **DD Image**) atau balenaEtcher |

### 2. Boot dari flashdisk
- **MacBook Pro A1708**: matikan, tahan **Option (⌥)** saat menyalakan, pilih **EFI Boot**.
- **Acer Nitro V 16**: tekan **F2** (BIOS) lalu **matikan Secure Boot**; tekan **F12** untuk boot menu dan pilih flashdisk. Jika SSD NVMe tidak terdeteksi saat instalasi, ubah mode **Intel VMD/RST** ke **AHCI** di BIOS.

Keyboard & trackpad internal MacBook (SPI) dan WMI Acer sudah dimuat di initramfs Live USB.

### 3. Instal
Di tty1 muncul layar sambutan: tekan **Enter** untuk memulai installer (atau `s` untuk shell). Installer bisa dijalankan ulang kapan saja dengan:

```bash
arch-v3-install
```

Yang dilakukan installer:
1. Cek mode UEFI, deteksi profil (MacBook / Acer), cek internet. Jika belum online: sambungkan Wi-Fi lewat menu (`iwctl`) atau pakai kabel LAN / USB tethering. Profil Wi-Fi otomatis disalin ke sistem baru.
2. Pilih disk (Live USB otomatis disembunyikan dari daftar). Mode **otomatis**: GPT, EFI 512 MB + root **ext4** atau **btrfs** (`@`, `@home`, zstd). Mode **manual**: Anda partisi/mount sendiri (cocok untuk dual-boot).
3. Isi hostname, user (sudo), password, timezone (default `Asia/Jakarta`).
4. `pacstrap` + konfigurasi + **GRUB UEFI** (dengan jalur fallback `EFI/BOOT` agar muncul di menu Option MacBook). ZRAM dan parameter kernel MacBook sudah terpasang.
5. Pilih **satu** desktop environment untuk sistem terpasang: KDE Plasma, GNOME, XFCE, atau Hyprland. Hanya desktop yang dipilih yang akan dipasang (bukan keempatnya). Live USB sendiri memakai XFCE. Setup perangkat, driver, audio, dan kipas dijalankan sebagai service first-boot. Progres: `journalctl -fu arch-v3-firstboot`, log: `/var/log/arch-v3-firstboot.log`. Jika gagal (mis. internet putus), otomatis dicoba lagi saat boot berikutnya, atau manual: `sudo systemctl start arch-v3-firstboot`. Jika sukses, sistem reboot sendiri.

> Mode otomatis **menghapus seluruh disk** tujuan. Untuk dual-boot dengan macOS/Windows gunakan mode manual.

### Isi repository
| File | Fungsi |
|---|---|
| `build-iso.sh` | Membangun ISO (dipanggil workflow di container Arch) |
| `install-arch-live.sh` | Installer interaktif di dalam Live USB |
| `arch-v3-welcome.sh` | Layar sambutan tty1 di Live USB |
| `make-live-usb.sh` | Menulis ISO ke flashdisk (Linux/macOS) |
| `setup-arch-v3-dual.sh` | Setup pasca-instalasi (juga bisa dijalankan manual di Arch yang sudah terpasang) |

## Cara Mencetak File `.iso` di GitHub (Sama Seperti Sebelumnya):
1. Ekstrak file ZIP ini dan upload seluruh isinya ke repository GitHub kamu.
2. Tunggu sekitar 10-15 menit di tab **Actions**.
3. Unduh file `.iso` (dan `.sha256`) yang sudah matang di bagian **Releases**, lalu tulis ke flashdisk (lihat di atas).


## Status integrasi Calamares (penting)

Sumber ini sekarang menyertakan paket Calamares dan entry-point GUI dengan dialog pilihan desktop. **Namun integrasi ini belum layak disebut final/teruji**: lingkungan pembuatan saat ini tidak menyediakan Arch Linux + `mkarchiso` atau VM bootable untuk menguji proses partisi, instalasi paket, GRUB UEFI, dan penerapan desktop pilihan dari awal sampai akhir. Dialog menyimpan pilihan, tetapi belum diklaim sebagai handoff instalasi yang telah tervalidasi. Jangan gunakan untuk memasang ke disk utama sebelum build ISO dan pengujian VM selesai. Installer TUI lama masih disertakan sebagai referensi/pemulihan.


## Catatan perbaikan workflow build (2026-10)

Skrip build diperbaiki agar pembuatan akun `liveuser` dilakukan melalui `airootfs/root/customize_airootfs.sh` di dalam root filesystem hasil build, bukan saat `airootfs` masih berupa overlay. Blok `sed` multiline yang sebelumnya rusak dan menyebabkan `unknown command: [` juga dihapus. Perubahan ini memperbaiki dua penyebab yang tampak pada log, tetapi build ISO tetap harus dijalankan ulang dan seluruh ISO belum dinyatakan teruji.


## Build-fix 2 (2026-10)

This revision builds the `calamares` AUR package in a non-root `builder` account, creates a local pacman repository for it, and adds that repository to the archiso profile. XFCE group names were replaced with explicit package names to avoid interactive package-group selection in CI. This addresses the specific `target not found: calamares` error and the group-selection prompt in the supplied GitHub Actions log. The build still depends on the current AUR PKGBUILD and upstream dependencies; it must be run in Actions to verify. **This does not complete or validate the Calamares installation configuration, partitioning, bootloader, or desktop-choice integration. Test only in a disposable VM.**
