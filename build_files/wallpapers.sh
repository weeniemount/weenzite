dnf5 install --skip-unavailable -y \
  f21-backgrounds-kde \
  f22-backgrounds-kde \
  f23-backgrounds-kde \
  f24-backgrounds-kde \
  f25-backgrounds-kde \
  f26-backgrounds-kde \
  f27-backgrounds-kde \
  f28-backgrounds-kde \
  f29-backgrounds-kde \
  f30-backgrounds-kde \
  f31-backgrounds-kde \
  f32-backgrounds-kde \
  f33-backgrounds-kde \
  f34-backgrounds-kde \
  f35-backgrounds-kde \
  f36-backgrounds-kde \
  f37-backgrounds-kde \
  f38-backgrounds-kde \
  f39-backgrounds-kde \
  f40-backgrounds-kde \
  f41-backgrounds-kde \
  f42-backgrounds-kde \
  f43-backgrounds-kde \
  fedora-eln-backgrounds \
  fedorainfinity-backgrounds \
  gears-backgrounds \
  neon-backgrounds \
  solar-backgrounds \
  desktop-backgrounds-basic \
  constantine-backgrounds \
  leonidas-backgrounds \
  goddard-backgrounds-kde \
  laughlin-backgrounds-kde \
  lovelock-backgrounds-kde \
  verne-backgrounds-kde \
  beefy-miracle-backgrounds-kde \
  spherical-cow-backgrounds-kde \
  schroedinger-cat-backgrounds-kde
# microwave gave me these commands
dnf5 -y copr enable horizonproject/horizon
dnf5 install -y horizon-backgrounds
dnf5 -y copr disable horizonproject/horizon
# fix old wallpaper metadata so they show up in system settings
find /usr/share/wallpapers -name "metadata.desktop" | while read desktop; do
    dir=$(dirname "$desktop")
    json="$dir/metadata.json"

    [ -f "$json" ] && continue

    name=$(grep "^Name=" "$desktop" | cut -d= -f2)
    email=$(grep "^X-KDE-PluginInfo-Email=" "$desktop" | cut -d= -f2)
    author=$(grep "^X-KDE-PluginInfo-Author=" "$desktop" | cut -d= -f2)
    id=$(grep "^X-KDE-PluginInfo-Name=" "$desktop" | cut -d= -f2)
    license=$(grep "^X-KDE-PluginInfo-License=" "$desktop" | cut -d= -f2)

    cat > "$json" <<EOF
{
    "KPlugin": {
        "Authors": [
            {
                "Email": "$email",
                "Name": "$author"
            }
        ],
        "Id": "$id",
        "Name": "$name",
        "License": "$license"
    }
}
EOF

    echo "created: $json"
done