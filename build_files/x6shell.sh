#!/bin/bash

set -ouex pipefail

DEVEL_PKGS="qt6-qtwebview-devel libepoxy-devel qt6-qtbase-private-devel layer-shell-qt-devel kf6-kwindowsystem-devel kf6-kcoreaddons-devel kf6-kwidgetsaddons-devel kf6-kconfigwidgets-devel kf6-kconfig-devel kf6-ki18n-devel kf6-kservice-devel kf6-kcmutils-devel extra-cmake-modules kf6-kcrash-devel kf6-kdbusaddons-devel kf6-kpackage-devel kf6-kxmlgui-devel kf6-kio-devel kf6-kstatusnotifieritem-devel kf6-knotifications-devel kf6-kiconthemes-devel plasma-activities-devel plasma-workspace-devel libplasma-devel kf6-kitemmodels-devel plasma-wayland-protocols-devel kwayland-devel"

printf '#!/bin/bash\nexec "$@"\n' > /usr/weenzite/slop/sudo
chmod +x /usr/weenzite/slop/sudo

echo "infusing with OSX"
echo "obtaining furnace"
dnf5 -y install gcc gcc-c++ make unzip kvantum git plasma-wayland-protocols $DEVEL_PKGS --skip-unavailable
echo "digging up sand"
git clone --depth=1 https://gitgud.io/x6shell/workspace/ x6shell
(
	cd x6shell
	echo "smelting sand and turning it into OSX"
	PATH="/usr/weenzite/slop:$PATH" bash install.sh
	echo "OSX smelted"
)
echo "digging up more sand"
git clone --depth=1 https://gitgud.io/x6shell/aurora aurora
(
	cd aurora
	echo "smelting sand into aurora"
	sed -i 's/find_package(Plymouth REQUIRED)/find_package(Plymouth)/' CMakeLists.txt
	sed -i 's/^add_subdirectory(plymouth)$/if(Plymouth_FOUND)\n    add_subdirectory(plymouth)\nendif()/' CMakeLists.txt

	PATH="/usr/weenzite/slop:$PATH" bash install.sh
	echo "aurora smelted"
)
echo "digging up even more sand"
git clone --depth=1 https://gitgud.io/x6shell/cougar cougar
(
	cd cougar
	echo "smelting sand into cougar"
	cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POSITION_INDEPENDENT_CODE=ON
	cmake --build build
	PATH="/usr/weenzite/slop:$PATH" sudo cmake --install build
	echo "cougar smelted"
)
echo "digging up the last bit of sand"
git clone --depth=1 https://gitgud.io/x6shell/kwin-components kwin-components
(
	cd kwin-components
	echo "smelting sand into kwin-components"
	chmod +x ./install.sh
	PATH="/usr/weenzite/slop:$PATH" ./install.sh
	echo "kwin-components smelted"
)
echo "cleaning up"
rm -rf x6shell
rm -rf aurora
rm -rf cougar
rm -rf kwin-components
rm -rf /usr/weenzite/slop/sudo
