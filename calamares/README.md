# Calamares integration status

This directory is an integration scaffold for the Arch V3 ISO build. The build adds Calamares and launches it from the XFCE desktop. The current environment did not have Arch Linux, `mkarchiso`, or a bootable VM available, so the resulting ISO has **not** been built or validated here. Do not treat this source ZIP as a tested, ready-to-flash ISO.

Calamares needs an Arch-specific installation configuration and a VM test before this can be considered production-ready. In particular, partitioning, package installation, bootloader installation, and the desktop-choice handoff must all be tested together. The previous TUI installer remains in the repository as a recovery/reference path and is not silently represented as Calamares.
