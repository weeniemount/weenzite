#!/bin/bash

set -ouex pipefail

bash /ctx/cros/build-chromeos-ash.sh
bash /ctx/aeros.sh
bash /ctx/x6shell.sh

dnf5 install -y tmux qemu libvirt guestfs-tools btop fira-code-fonts jetbrains-mono-fonts cowsay plasma-oxygen 

#titanoboa stuff (why did they make it more complicated to build a live iso :wilted_rose)
dnf5 install -y grub2-efi-x64 grub2-efi-x64-cdboot grub2-pc grub2-pc-modules shim-x64 grub2-tools grub2-tools-extra

bash /ctx/wallpapers.sh

# download ween stuff

# download google balls
curl -L -o /tmp/gtk-app-linux-x64.tar.gz \
  https://github.com/weeniemount/googleballs-app/releases/latest/download/gtk-app-linux-x64.tar.gz
tar -xzf /tmp/gtk-app-linux-x64.tar.gz -C /usr/weenzite/balls --no-same-owner
rm -f /usr/weenzite/balls/README.txt
rm -f /tmp/gtk-app-linux-x64.tar.gz

# download the news

curl -L -o /usr/weenzite/news/thenews \
  https://github.com/weeniemount/thenews-linux/releases/latest/download/thenews
chmod +x /usr/weenzite/news/thenews

# end of download ween stuff

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

sed -i -e 's/^ID=.*/ID=fedora/' /usr/lib/os-release
grep -q '^ID_LIKE=' /usr/lib/os-release || echo 'ID_LIKE=fedora' >> /usr/lib/os-release

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

systemctl enable libvirtd.service
systemctl enable podman.socket


if [ -f /etc/passwd ]; then
    out=$(grep -v "root" /etc/passwd) || true
    if [ -n "$out" ]; then
        echo
        echo Moving the following passwd users to /usr/lib/passwd
        echo "$out"
        echo "$out" >> /usr/lib/passwd
        echo "root:x:0:0:root:/root:/bin/bash" > /etc/passwd
    fi
fi
if [ -f /etc/group ]; then
    out=$(grep -v "root\|wheel" /etc/group) || true
    if [ -n "$out" ]; then
        echo
        echo Moving the following group entries to /usr/lib/group
        echo "$out"
        echo "$out" >> /usr/lib/group
        echo "root:x:0:" > /etc/group
        echo "wheel:x:10:" >> /etc/group
    fi
fi

# and then forcefully rebuild initrd!!!!... maybe this one will work
QUALIFIED_KERNEL="$(dnf5 repoquery --installed --queryformat='%{evr}.%{arch}' "kernel")"
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible --zstd -v --add ostree --add fido2 -f "/usr/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 /usr/lib/modules/"$QUALIFIED_KERNEL"/initramfs.img
