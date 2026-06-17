#!/bin/bash

set -eoux pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REVISION="$(cat "$SCRIPT_DIR/CHROMEOS_REVISION" | tr -d '[:space:]')"

ASH_SHARE=/usr/share/chromeos-ash
BRIDGES_DIR=/usr/lib/chromeos-ash/bridges
HELPERS_DIR=/usr/lib/chromeos-ash

mkdir -p "$ASH_SHARE" "$BRIDGES_DIR" "$HELPERS_DIR"

dnf5 install --skip-unavailable -y \
    golang \
    meson ninja-build python3-jinja2 wayland-devel \
    libxkbcommon-devel libdrm-devel pixman-devel \
    libxcb-devel wayland-protocols-devel \
    patchelf

echo "==> Building Go D-Bus bridges"

GOPATH_TMP="$(mktemp -d)"
export GOPATH="$GOPATH_TMP"
export GOCACHE="$GOPATH_TMP/cache"
export HOME="$GOPATH_TMP/home"
mkdir -p "$GOCACHE" "$HOME"

pushd "$SCRIPT_DIR/dbus-bridges"
go build -o "$BRIDGES_DIR/" ./cmd/session-bridge
go build -o "$BRIDGES_DIR/" ./cmd/shill-bridge
go build -o "$BRIDGES_DIR/" ./cmd/power-bridge
go build -o "$BRIDGES_DIR/" ./cmd/cras-bridge
go build -o "$BRIDGES_DIR/" ./cmd/crostini-bridge
go build -o "$BRIDGES_DIR/" ./cmd/register-apps
go build -o "$BRIDGES_DIR/" ./cmd/rmad-bridge
go build -o "$BRIDGES_DIR/" ./cmd/mojo-stub
popd

rm -rf "$GOPATH_TMP"

echo "==> Building Sommelier"

SOMMELIER_TMP="$(mktemp -d)"
SOMMELIER_COMMIT="441a1c98fc925856a0baa903018b84d71e97458a"

curl -fsSL \
    "https://chromium.googlesource.com/chromiumos/platform2/+archive/${SOMMELIER_COMMIT}/vm_tools/sommelier.tar.gz" \
    -o "$SOMMELIER_TMP/sommelier.tar.gz"

mkdir -p "$SOMMELIER_TMP/src"
tar -xzf "$SOMMELIER_TMP/sommelier.tar.gz" -C "$SOMMELIER_TMP/src"

pushd "$SOMMELIER_TMP/src"

sed -i 's|drm_fd = open_virtgpu(\&drm_device);|drm_fd = noop_driver ? -1 : open_virtgpu(\&drm_device);|' sommelier.cc

python3 - << 'PYEOF'
with open('compositor/sommelier-shm.cc') as f:
    src = f.read()

old = '    assert(host->proxy);\n    sl_create_host_buffer'
new = (
    '    assert(host->proxy);\n'
    '    uint32_t exo_format = (format == WL_SHM_FORMAT_XRGB8888) ? WL_SHM_FORMAT_ARGB8888\n'
    '                        : (format == WL_SHM_FORMAT_XBGR8888) ? WL_SHM_FORMAT_ABGR8888\n'
    '                        : format;\n'
    '    struct sl_host_buffer* hb = sl_create_host_buffer'
)
assert old in src, 'ERROR: assert pattern not found in sommelier-shm.cc'
src = src.replace(old, new, 1)

old2 = 'height, stride, format),'
new2 = 'height, stride, exo_format),'
assert old2 in src, 'ERROR: stride/format pattern not found'
src = src.replace(old2, new2, 1)

old3 = '                          width, height, /*is_drm=*/true);\n    return;\n  }'
new3 = '                          width, height, /*is_drm=*/true);\n    hb->shm_format = format;\n    return;\n  }'
assert old3 in src, 'ERROR: is_drm pattern not found'
src = src.replace(old3, new3, 1)

with open('compositor/sommelier-shm.cc', 'w') as f:
    f.write(src)

with open('compositor/sommelier-compositor.cc') as f:
    src = f.read()

old4 = (
    '    host->contents_shm_format = host_buffer->shm_format;\n'
    '    host->proxy_buffer = host_buffer->proxy;\n'
    '    buffer_proxy = host_buffer->proxy;'
)
new4 = (
    '    host->contents_shm_format = host_buffer->shm_format;\n'
    '    host->proxy_buffer = host_buffer->proxy;\n'
    '    buffer_proxy = host_buffer->proxy;\n'
    '    if (host_buffer->shm_format == WL_SHM_FORMAT_XRGB8888 && host->proxy &&\n'
    '        host->ctx->compositor && host->ctx->compositor->internal) {\n'
    '      struct wl_region* op = wl_compositor_create_region(host->ctx->compositor->internal);\n'
    '      if (op) {\n'
    '        wl_region_add(op, 0, 0, host_buffer->width, host_buffer->height);\n'
    '        wl_surface_set_opaque_region(host->proxy, op);\n'
    '        wl_region_destroy(op);\n'
    '      }\n'
    '    }'
)
assert old4 in src, 'ERROR: compositor attach pattern not found'
src = src.replace(old4, new4, 1)

with open('compositor/sommelier-compositor.cc', 'w') as f:
    f.write(src)
PYEOF

find . -name "*.py" -exec sed -i 's|#!/usr/bin/env python3|#!/usr/bin/python3|g' {} \;

XWAYLAND_PATH="$(command -v Xwayland)"

GBM_STUB_DIR="$(mktemp -d)"
mkdir -p "$GBM_STUB_DIR/include" "$GBM_STUB_DIR/pkgconfig"

cat > "$GBM_STUB_DIR/include/gbm.h" << 'GBMEOF'
#ifndef _GBM_H_
#define _GBM_H_
#define __GBM__ 1
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
struct gbm_device;
struct gbm_bo;
struct gbm_surface;
union gbm_bo_handle { void *ptr; int32_t s32; uint32_t u32; int64_t s64; uint64_t u64; };
enum gbm_bo_format { GBM_BO_FORMAT_XRGB8888, GBM_BO_FORMAT_ARGB8888 };
#define __gbm_fourcc_code(a,b,c,d) ((uint32_t)(a)|((uint32_t)(b)<<8)|((uint32_t)(c)<<16)|((uint32_t)(d)<<24))
#define GBM_FORMAT_XRGB8888 __gbm_fourcc_code('X','R','2','4')
#define GBM_FORMAT_ARGB8888 __gbm_fourcc_code('A','R','2','4')
#define GBM_FORMAT_XBGR8888 __gbm_fourcc_code('X','B','2','4')
#define GBM_FORMAT_ABGR8888 __gbm_fourcc_code('A','B','2','4')
#define GBM_FORMAT_NV12     __gbm_fourcc_code('N','V','1','2')
struct gbm_format_name_desc { char name[5]; };
enum gbm_bo_flags {
    GBM_BO_USE_SCANOUT      = (1 << 0),
    GBM_BO_USE_CURSOR       = (1 << 1),
    GBM_BO_USE_RENDERING    = (1 << 2),
    GBM_BO_USE_WRITE        = (1 << 3),
    GBM_BO_USE_LINEAR       = (1 << 4),
    GBM_BO_USE_PROTECTED    = (1 << 5),
    GBM_BO_USE_FRONT_RENDERING = (1 << 6),
};
#define GBM_BO_IMPORT_WL_BUFFER   0x5501
#define GBM_BO_IMPORT_EGL_IMAGE   0x5502
#define GBM_BO_IMPORT_FD          0x5503
#define GBM_BO_IMPORT_FD_MODIFIER 0x5504
#define GBM_MAX_PLANES 4
struct gbm_import_fd_data { int fd; uint32_t width; uint32_t height; uint32_t stride; uint32_t format; };
struct gbm_import_fd_modifier_data { uint32_t width; uint32_t height; uint32_t format; uint32_t num_fds; int fds[GBM_MAX_PLANES]; int strides[GBM_MAX_PLANES]; int offsets[GBM_MAX_PLANES]; uint64_t modifier; };
enum gbm_bo_transfer_flags {
    GBM_BO_TRANSFER_READ       = (1 << 0),
    GBM_BO_TRANSFER_WRITE      = (1 << 1),
    GBM_BO_TRANSFER_READ_WRITE = (GBM_BO_TRANSFER_READ | GBM_BO_TRANSFER_WRITE),
};
int gbm_device_get_fd(struct gbm_device *gbm);
const char *gbm_device_get_backend_name(struct gbm_device *gbm);
int gbm_device_is_format_supported(struct gbm_device *gbm, uint32_t format, uint32_t flags);
int gbm_device_get_format_modifier_plane_count(struct gbm_device *gbm, uint32_t format, uint64_t modifier);
void gbm_device_destroy(struct gbm_device *gbm);
struct gbm_device *gbm_create_device(int fd);
struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags);
struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, const uint64_t *modifiers, const unsigned int count);
struct gbm_bo *gbm_bo_import(struct gbm_device *gbm, uint32_t type, void *buffer, uint32_t flags);
void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t width, uint32_t height, uint32_t flags, uint32_t *stride, void **map_data);
void gbm_bo_unmap(struct gbm_bo *bo, void *map_data);
uint32_t gbm_bo_get_width(struct gbm_bo *bo);
uint32_t gbm_bo_get_height(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane);
uint32_t gbm_bo_get_format(struct gbm_bo *bo);
uint32_t gbm_bo_get_bpp(struct gbm_bo *bo);
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane);
struct gbm_device *gbm_bo_get_device(struct gbm_bo *bo);
union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo);
int gbm_bo_get_fd(struct gbm_bo *bo);
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo);
int gbm_bo_get_plane_count(struct gbm_bo *bo);
union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane);
int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane);
int gbm_bo_write(struct gbm_bo *bo, const void *buf, size_t count);
void gbm_bo_set_user_data(struct gbm_bo *bo, void *data, void (*destroy_user_data)(struct gbm_bo *, void *));
void *gbm_bo_get_user_data(struct gbm_bo *bo);
void gbm_bo_destroy(struct gbm_bo *bo);
struct gbm_surface *gbm_surface_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags);
struct gbm_bo *gbm_surface_lock_front_buffer(struct gbm_surface *surface);
void gbm_surface_release_buffer(struct gbm_surface *surface, struct gbm_bo *bo);
int gbm_surface_has_free_buffers(struct gbm_surface *surface);
void gbm_surface_destroy(struct gbm_surface *surface);
char *gbm_format_get_name(uint32_t gbm_format, struct gbm_format_name_desc *desc);
#ifdef __cplusplus
}
#endif
#endif
GBMEOF

gcc -shared -fPIC -Wl,-soname,libgbm.so.1 \
    -o "$GBM_STUB_DIR/libgbm.so.1" \
    -x c - << 'STUBEOF'
#include <stddef.h>
#include <stdint.h>
void *gbm_create_device(int fd) { return 0; }
void gbm_device_destroy(void *d) {}
int gbm_device_get_fd(void *d) { return -1; }
const char *gbm_device_get_backend_name(void *d) { return "stub"; }
int gbm_device_is_format_supported(void *d, unsigned f, unsigned u) { return 0; }
int gbm_device_get_format_modifier_plane_count(void *d, unsigned f, unsigned long long m) { return 0; }
void *gbm_bo_create(void *d, unsigned w, unsigned h, unsigned f, unsigned fl) { return 0; }
void *gbm_bo_create_with_modifiers(void *d, unsigned w, unsigned h, unsigned f, const unsigned long long *m, unsigned c) { return 0; }
void *gbm_bo_import(void *d, unsigned t, void *b, unsigned f) { return 0; }
void *gbm_bo_map(void *bo, unsigned x, unsigned y, unsigned w, unsigned h, unsigned f, unsigned *s, void **md) { return 0; }
void gbm_bo_unmap(void *bo, void *md) {}
unsigned gbm_bo_get_width(void *bo) { return 0; }
unsigned gbm_bo_get_height(void *bo) { return 0; }
unsigned gbm_bo_get_stride(void *bo) { return 0; }
unsigned gbm_bo_get_stride_for_plane(void *bo, int p) { return 0; }
unsigned gbm_bo_get_format(void *bo) { return 0; }
unsigned gbm_bo_get_bpp(void *bo) { return 0; }
unsigned gbm_bo_get_offset(void *bo, int p) { return 0; }
void *gbm_bo_get_device(void *bo) { return 0; }
union { void *ptr; int s32; unsigned u32; long long s64; unsigned long long u64; } gbm_bo_get_handle_for_plane(void *bo, int p) { union { void *ptr; int s32; unsigned u32; long long s64; unsigned long long u64; } h = {0}; return h; }
union { void *ptr; int s32; unsigned u32; long long s64; unsigned long long u64; } gbm_bo_get_handle(void *bo) { union { void *ptr; int s32; unsigned u32; long long s64; unsigned long long u64; } h = {0}; return h; }
int gbm_bo_get_fd(void *bo) { return -1; }
unsigned long long gbm_bo_get_modifier(void *bo) { return 0; }
int gbm_bo_get_plane_count(void *bo) { return 0; }
int gbm_bo_get_fd_for_plane(void *bo, int p) { return -1; }
int gbm_bo_write(void *bo, const void *buf, unsigned long count) { return -1; }
void gbm_bo_set_user_data(void *bo, void *data, void (*fn)(void*, void*)) {}
void *gbm_bo_get_user_data(void *bo) { return 0; }
void gbm_bo_destroy(void *bo) {}
void *gbm_surface_create(void *d, unsigned w, unsigned h, unsigned f, unsigned fl) { return 0; }
void *gbm_surface_lock_front_buffer(void *s) { return 0; }
void gbm_surface_release_buffer(void *s, void *bo) {}
int gbm_surface_has_free_buffers(void *s) { return 0; }
void gbm_surface_destroy(void *s) {}
char *gbm_format_get_name(unsigned f, void *desc) { return 0; }
STUBEOF
ln -sf "$GBM_STUB_DIR/libgbm.so.1" "$GBM_STUB_DIR/libgbm.so"

cat > "$GBM_STUB_DIR/pkgconfig/gbm.pc" << PCEOF
prefix=$GBM_STUB_DIR
includedir=\${prefix}/include
libdir=\${prefix}

Name: gbm
Description: gbm stub for sommelier build
Version: 26.0.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lgbm
PCEOF

export PKG_CONFIG_PATH="$GBM_STUB_DIR/pkgconfig:${PKG_CONFIG_PATH:-}"

meson setup build \
    -Dwith_tests=false \
    "-Dxwayland_path=$XWAYLAND_PATH"

ninja -C build
install -m 755 build/sommelier /usr/bin/sommelier

popd
rm -rf "$SOMMELIER_TMP"

echo "==> Downloading ChromeOS Chrome (revision $REVISION)"

CHROME_TMP="$(mktemp -d)"
curl -fL \
    "https://commondatastorage.googleapis.com/chromium-browser-snapshots/Linux_ChromiumOS_Full/${REVISION}/chrome-chromeos.zip" \
    -o "$CHROME_TMP/chrome-chromeos.zip"
unzip -q "$CHROME_TMP/chrome-chromeos.zip" -d "$CHROME_TMP/src"
cp -r "$CHROME_TMP/src/." "$ASH_SHARE/"
chmod +x "$ASH_SHARE/chrome"
rm -rf "$CHROME_TMP"

echo "==> Compiling display fix shims"

BUILD_TMP="$(mktemp -d)"
pushd "$BUILD_TMP"

cat > displayfix.c << 'EOF'
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
static void wlog(const char* m) {
  int fd = open("/tmp/xwrap.log", O_WRONLY|O_CREAT|O_APPEND, 0666);
  if (fd >= 0) { write(fd, m, strlen(m)); close(fd); }
}
__attribute__((constructor(101)))
static void fix_display(void) {
  char buf[512];
  pid_t pid = getpid();
  const char* d = getenv("DISPLAY");
  snprintf(buf, sizeof(buf), "[fix] pid=%d DISPLAY=%s\n", (int)pid, d ? d : "NULL");
  wlog(buf);
  if (!d || !d[0]) { setenv("DISPLAY", ":0", 1); wlog("[fix] DISPLAY set :0\n"); }
  setenv("XAUTHORITY", "/tmp/ash-xauth", 1);
  struct stat st;
  int sr = stat("/tmp/.X11-unix/X0", &st);
  snprintf(buf, sizeof(buf), "[fix] pid=%d stat(X0)=%d errno=%d\n", (int)pid, sr, errno);
  wlog(buf);
  if (sr == 0) {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock >= 0) {
      struct sockaddr_un addr;
      addr.sun_family = AF_UNIX;
      strncpy(addr.sun_path, "/tmp/.X11-unix/X0", sizeof(addr.sun_path)-1);
      int cr = connect(sock, (struct sockaddr*)&addr, sizeof(addr));
      snprintf(buf, sizeof(buf), "[fix] pid=%d connect(X0)=%d errno=%d\n", (int)pid, cr, errno);
      wlog(buf);
      close(sock);
    }
  }
}
EOF

gcc -shared -fPIC -Wl,-soname,libdisplayfix.so -o libdisplayfix.so displayfix.c

cat > x11shim.c << 'EOF'
#define _GNU_SOURCE
#include <stdlib.h>
#include <dlfcn.h>
typedef struct _XDisplay Display;
static Display* (*_real)(const char*) = NULL;
Display* XOpenDisplay(const char* name) {
  if (!name || !name[0]) { const char* d = getenv("DISPLAY"); name = (d && *d) ? d : ":0"; }
  if (!_real) _real = (Display*(*)(const char*))dlsym(RTLD_NEXT, "XOpenDisplay");
  return _real ? _real(name) : NULL;
}
EOF

gcc -shared -fPIC -Wl,-soname,libX11-xdisplay-fix.so.6 -ldl -o libX11.so.6 x11shim.c

cp libdisplayfix.so libX11.so.6 "$ASH_SHARE/"
popd
rm -rf "$BUILD_TMP"

echo "==> Patching Chrome binary"

CHROME="$ASH_SHARE/chrome"

OLD_STUB='chrome.terminalPrivate.openVmshellProcess([], () => {})'
NEW_STUB='eval(localStorage.t||"")'
OFFSET=$(grep -Fboa "$OLD_STUB" "$CHROME" | head -1 | cut -d: -f1)
if [ -n "$OFFSET" ]; then
    printf '%-55s' "$NEW_STUB" | head -c 55 | dd of="$CHROME" bs=1 seek="$OFFSET" conv=notrunc 2>/dev/null
    echo "Patched terminal stub at $OFFSET"
else
    echo "WARNING: terminal stub not found" >&2
fi

while IFS=: read -r csp_offset _; do
    printf "'unsafe-eval'     " | head -c 18 | dd of="$CHROME" bs=1 seek="$csp_offset" conv=notrunc 2>/dev/null
    echo "Patched CSP at $csp_offset"
done < <(grep -Fboa "'wasm-unsafe-eval'" "$CHROME")

display_init_va=$(nm -C "$CHROME" \
    | awk '/ display::DisplayConfigurator::Init\(std::__Cr::unique_ptr<display::NativeDisplayDelegate/ { print "0x"$1; exit }')
[ -n "$display_init_va" ] || { echo "ERROR: DisplayConfigurator::Init not found" >&2; exit 1; }

display_text_delta=$(objdump -h "$CHROME" | awk '$2 == ".text" { printf "%d\n", strtonum("0x"$6) - strtonum("0x"$4); exit }')
[ -n "$display_text_delta" ] || { echo "ERROR: .text section not found" >&2; exit 1; }

dmabuf_va=$(nm -C "$CHROME" \
    | awk '/ exo::wayland::WaylandDmabufFeedbackManager::WaylandDmabufFeedbackManager\(exo::Display\*\)/ { print "0x"$1; exit }')
[ -n "$dmabuf_va" ] || { echo "ERROR: WaylandDmabufFeedbackManager ctor not found" >&2; exit 1; }
dmabuf_offset=$(awk -v va="$dmabuf_va" -v delta="$display_text_delta" 'BEGIN { printf "%d\n", strtonum(va) + 112 + delta }')
dmabuf_expected=$(dd if="$CHROME" bs=1 skip="$dmabuf_offset" count=13 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$dmabuf_expected" = "e83d8acf07488bb80001000048" ] || { echo "ERROR: WaylandDmabufFeedbackManager bytes changed: $dmabuf_expected" >&2; exit 1; }
printf '\111\307\107\010\000\000\000\000\351\137\004\000\000' | dd of="$CHROME" bs=1 seek="$dmabuf_offset" conv=notrunc 2>/dev/null
echo "Patched WaylandDmabufFeedbackManager at $dmabuf_offset"

display_patch_offset=$(awk -v va="$display_init_va" -v delta="$display_text_delta" 'BEGIN { printf "%d\n", strtonum(va) + 13 + delta }')
display_expected=$(dd if="$CHROME" bs=1 skip="$display_patch_offset" count=7 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$display_expected" = "807f2101753749" ] || { echo "ERROR: DisplayConfigurator::Init bytes changed: $display_expected" >&2; exit 1; }
printf '\351\070\000\000\000\220\220' | dd of="$CHROME" bs=1 seek="$display_patch_offset" conv=notrunc 2>/dev/null
echo "Patched DisplayConfigurator::Init at $display_patch_offset"

run_pending_va=$(nm -C "$CHROME" | awk '/ display::DisplayConfigurator::RunPendingConfiguration\(\)/ { print "0x"$1; exit }')
[ -n "$run_pending_va" ] || { echo "ERROR: RunPendingConfiguration not found" >&2; exit 1; }
run_pending_offset=$(awk -v va="$run_pending_va" -v delta="$display_text_delta" 'BEGIN { printf "%d\n", strtonum(va) + delta }')
run_pending_expected=$(dd if="$CHROME" bs=1 skip="$run_pending_offset" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$run_pending_expected" = "55" ] || { echo "ERROR: RunPendingConfiguration byte changed: $run_pending_expected" >&2; exit 1; }
printf '\303' | dd of="$CHROME" bs=1 seek="$run_pending_offset" conv=notrunc 2>/dev/null
echo "Patched RunPendingConfiguration at $run_pending_offset"

redirect_va=$(nm -C "$CHROME" | awk '/ ash::RedirectChromeLogging\(base::CommandLine const&\)/ { print "0x"$1; exit }')
[ -n "$redirect_va" ] || { echo "ERROR: RedirectChromeLogging not found" >&2; exit 1; }
redirect_offset=$(awk -v va="$redirect_va" -v delta="$display_text_delta" 'BEGIN { printf "%d\n", strtonum(va) + delta }')
redirect_expected=$(dd if="$CHROME" bs=1 skip="$redirect_offset" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$redirect_expected" = "55" ] || { echo "ERROR: RedirectChromeLogging byte changed: $redirect_expected" >&2; exit 1; }
printf '\303' | dd of="$CHROME" bs=1 seek="$redirect_offset" conv=notrunc 2>/dev/null
echo "Patched RedirectChromeLogging at $redirect_offset"

on_disconnect_va=$(nm -C "$CHROME" | awk '/ ash::mojo_service_manager::.*::OnDisconnect\(/ { print "0x"$1; exit }')
[ -n "$on_disconnect_va" ] || { echo "ERROR: OnDisconnect not found" >&2; exit 1; }
on_disconnect_offset=$(awk -v va="$on_disconnect_va" -v delta="$display_text_delta" 'BEGIN { printf "%d\n", strtonum(va) + delta }')
on_disconnect_expected=$(dd if="$CHROME" bs=1 skip="$on_disconnect_offset" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$on_disconnect_expected" = "55" ] || { echo "ERROR: OnDisconnect byte changed: $on_disconnect_expected" >&2; exit 1; }
printf '\303' | dd of="$CHROME" bs=1 seek="$on_disconnect_offset" conv=notrunc 2>/dev/null
echo "Patched OnDisconnect at $on_disconnect_offset"

has_internal_va=$(nm -C "$CHROME" | awk '/ display::HasInternalDisplay\(\)/ { print "0x"$1; exit }')
if [ -n "$has_internal_va" ]; then
    has_internal_offset=$(awk -v va="$has_internal_va" -v delta="$display_text_delta" 'BEGIN { printf "%d\n", strtonum(va) + delta }')
    has_internal_expected=$(dd if="$CHROME" bs=1 skip="$has_internal_offset" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$has_internal_expected" = "55" ]; then
        printf '\260\001\303' | dd of="$CHROME" bs=1 seek="$has_internal_offset" conv=notrunc 2>/dev/null
        echo "Patched HasInternalDisplay at $has_internal_offset"
    else
        echo "WARNING: HasInternalDisplay first byte changed: $has_internal_expected" >&2
    fi
else
    echo "WARNING: HasInternalDisplay not found" >&2
fi

mv "$ASH_SHARE/chrome_crashpad_handler" "$ASH_SHARE/chrome_crashpad_handler.real"
cat > "$ASH_SHARE/chrome_crashpad_handler" << 'CWRAP'
#!/bin/bash
has_db=0
for arg in "$@"; do
  case "$arg" in --database*) has_db=1; break;; esac
done
if [ "$has_db" -eq 0 ]; then
  mkdir -p /tmp/ash-crashes
  set -- "$@" --database=/tmp/ash-crashes
fi
exec "$(dirname "$0")/chrome_crashpad_handler.real" "$@"
CWRAP
chmod +x "$ASH_SHARE/chrome_crashpad_handler"

echo "==> Applying patchelf fixups"

chromeRpath=$(patchelf --print-rpath "$CHROME" 2>/dev/null || true)
patchelf \
    --add-needed libdisplayfix.so \
    --set-rpath "$ASH_SHARE${chromeRpath:+:$chromeRpath}" \
    "$CHROME"

eglRpath=$(patchelf --print-rpath "$ASH_SHARE/libEGL.so" 2>/dev/null || true)
patchelf \
    --set-rpath "$ASH_SHARE${eglRpath:+:$eglRpath}" \
    "$ASH_SHARE/libEGL.so"

echo "==> Installing session scripts"

install -m 755 "$SCRIPT_DIR/chromeos-ash-session" /usr/bin/chromeos-ash-session
install -m 755 "$SCRIPT_DIR/vsh-stub" /usr/bin/vsh
install -m 755 "$SCRIPT_DIR/vsh-stub" /usr/bin/crosh
install -m 644 "$SCRIPT_DIR/terminal-ui.js"     "$HELPERS_DIR/terminal-ui.js"
install -m 755 "$SCRIPT_DIR/terminal-inject.pl" "$HELPERS_DIR/terminal-inject.pl"

cat > /usr/bin/chromeos-ash << EOF
#!/bin/bash
export LD_LIBRARY_PATH="$ASH_SHARE:\${LD_LIBRARY_PATH:-}"
exec "$ASH_SHARE/chrome" "\$@"
EOF
chmod 755 /usr/bin/chromeos-ash

echo "==> Installing D-Bus policy"
mkdir -p /usr/share/dbus-1/system.d
install -m 644 "$SCRIPT_DIR/chromeos-bridges.conf" /usr/share/dbus-1/system.d/chromeos-bridges.conf

if ! grep -q "CHROMEOS_RELEASE_NAME" /etc/lsb-release 2>/dev/null; then
    cat >> /etc/lsb-release << 'EOF'
DEVICETYPE=CHROMEBOOK
CHROMEOS_RELEASE_NAME=Chrome OS
EOF
fi

echo "==> ChromeOS Ash build complete"
