#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux 


dnf5 install -y f37-backgrounds-kde f38-backgrounds-kde f39-backgrounds-kde f40-backgrounds-kde f42-backgrounds-kde f43-backgrounds-kde

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket


# download google balls

curl -L -o /tmp/gtk-app-linux-x64.tar.gz \
  https://github.com/weeniemount/googleballs-app/releases/latest/download/gtk-app-linux-x64.tar.gz

tar -xzf /tmp/gtk-app-linux-x64.tar.gz -C /usr/weenzite/balls --no-same-owner

rm -f /usr/weenzite/balls/README.txt

rm -f /tmp/gtk-app-linux-x64.tar.gz

# end of download google balls

# rebrand gaming
sed -i \
  -e '/image-ref/!s/bazzite-nvidia-open/weenzite/g' \
  -e '/image-ref/!s/ublue-os/weeniemount/g' \
  /usr/share/ublue-os/image-info.json

sed -i \
  -e '/^CPE_NAME/!s/Bazzite/Weenzite/g' \
  -e '/^CPE_NAME\|^BOOTLOADER_NAME\|^LOGO\|^IMAGE_ID/!s/bazzite/weenzite/g' \
  -e 's|HOME_URL=".*"|HOME_URL="https://github.com/weeniemount/weenzite"|' \
  -e 's|DOCUMENTATION_URL=".*"|DOCUMENTATION_URL="https://github.com/weeniemount/weenzite/wiki"|' \
  -e 's|SUPPORT_URL=".*"|SUPPORT_URL="https://github.com/weeniemount/weenzite/discussions"|' \
  -e 's|BUG_REPORT_URL=".*"|BUG_REPORT_URL="https://github.com/weeniemount/weenzite/issues/"|' \
  /usr/lib/os-release

# end of rebrand gaming


# more plasmoid gaming

# maxwell!

git clone https://github.com/wilversings/maxwell /usr/share/plasma/plasmoids/maxwell/

# new bouncy ball widget for kde plasma 6
git clone https://invent.kde.org/filipf/bouncy-ball /tmp/ball
mkdir -p /usr/share/plasma/plasmoids/org.kde.plasma.bouncyball
mv /tmp/ball/package/* /usr/share/plasma/plasmoids/org.kde.plasma.bouncyball/
rm -rf /tmp/ball

# end of more plasmoid gaming

# turn off the NTFS/exFAT partition mount nag stolen from quinces repo
systemctl --global disable ntfs-nag.service
rm /usr/lib/systemd/user/ntfs-nag.service
rm /usr/libexec/ntfs_exfat_monitor_script
