#!/bin/bash

set -ouex pipefail

DEVEL_PKGS="plasma-workspace-devel libksysguard-devel qt6-qtmultimedia-devel qt6-qt5compat-devel libplasma-devel qt6-qtbase-devel qt6-qtwayland-devel plasma-activities-devel kf6-kpackage-devel kf6-kglobalaccel-devel qt6-qtsvg-devel wayland-devel kf6-ksvg-devel kf6-kcrash-devel kf6-kguiaddons-devel kf6-kcmutils-devel kf6-kio-devel kdecoration-devel kf6-ki18n-devel kf6-knotifications-devel kf6-kirigami-devel kf6-kiconthemes-devel cmake gmp-ecm-devel kf5-plasma-devel libepoxy-devel kwin-devel kf6-karchive kf6-karchive-devel plasma-wayland-protocols-devel qt6-qtbase-private-devel qt6-qtbase-devel kf6-knewstuff-devel kf6-knotifyconfig-devel kf6-attica-devel kf6-krunner-devel kf6-kdbusaddons-devel kf6-sonnet-devel plasma5support-devel plasma-activities-stats-devel polkit-qt6-1-devel qt-devel libdrm-devel kf6-kitemmodels-devel kf6-kstatusnotifieritem-devel kf6-frameworkintegration-devel wayland-protocols-devel ninja cmake extra-cmake-modules"

echo "infusing with aeros"
echo "obtaining furnace"
dnf5 -y install gcc gcc-c++ make unzip kvantum git plasma-wayland-protocols $DEVEL_PKGS
echo "digging up sand"
git clone --depth=1 https://gitgud.io/wackyideas/aerothemeplasma.git aerothemeplasma
(
	cd aerothemeplasma
	echo "smelting sand and turning it into aeros"
	CMAKE_GENERATOR=Ninja bash install.sh --skip-x11
)
echo "cleaning up"
rm -rf aerothemeplasma
