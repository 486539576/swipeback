#!/bin/bash
# ============================================================================
#  上滑返回 —— macOS 云端构建脚本（GitHub Actions 内执行）
#  编译 3 个子项目 -> 收集 dylib/bundle -> 补 substrate 依赖为 .jbroot
#  -> 组装 deb 文件树 -> 打出一个 deb 包（格式不完美没关系，Linux 侧会重打包）
# ============================================================================
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"

# ---- 1. 准备 theos ----
if [ ! -d "$HOME/theos" ]; then
    echo ">>> installing theos..."
    git clone --recursive --depth 1 https://github.com/theos/theos.git "$HOME/theos"
    export THEOS="$HOME/theos"
    pushd "$THEOS"
    ./bootstrap --no-curl-cache
    popd
else
    export THEOS="$HOME/theos"
fi

# ---- 2. 编译 ----
echo ">>> make..."
make

# ---- 3. 组装文件树 ----
STAGE="$ROOT/stage"
rm -rf "$STAGE"
DL="$STAGE/Library/MobileSubstrate/DynamicLibraries"
PB="$STAGE/Library/PreferenceBundles/SwipeBackPrefs.bundle"
PL="$STAGE/Library/PreferenceLoader/Preferences"
mkdir -p "$DL" "$PB" "$PL"

cp AppTweak/.theos/obj/arm64e/SwipeBackApp.dylib "$DL/"
cp SBTweak/.theos/obj/arm64e/SwipeBackSB.dylib   "$DL/"
cp SwipeBackApp.plist  "$DL/SwipeBackApp.plist"
cp SwipeBackSB.plist   "$DL/SwipeBackSB.plist"
cp PrefsBundle/.theos/obj/arm64e/SwipeBackPrefs.bundle/SwipeBackPrefs "$PB/"
cp PrefsBundle/Root.plist "$PB/Root.plist"
cp PrefsBundle/SwipeBackPrefs-Info.plist "$PB/Info.plist"
cp SwipeBackPrefs.plist "$PL/SwipeBackPrefs.plist"

# ---- 4. 把 substrate 依赖改成 .jbroot（否则 RootHide 下 dyld 找不到）----
echo ">>> patching substrate path..."
for f in "$DL/SwipeBackApp.dylib" "$DL/SwipeBackSB.dylib"; do
    python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
target = b'@loader_path/.jbroot/usr/lib/libsubstrate.dylib'
d = d.replace(b'CydiaSubstrate', target.ljust(len(b'CydiaSubstrate'), b'\x00'))
open(p, 'wb').write(d)
print('patched', p)
PY
done

# ---- 5. 打 deb（仅作为承载文件树，Linux 侧会干净重打包）----
echo ">>> packaging deb..."
VER="0.2.87"
CTRL="$STAGE/DEBIAN/control"
mkdir -p "$STAGE/DEBIAN"
cat > "$CTRL" <<EOF
Package: com.doubao.swipeback
Name: 上滑返回
Version: $VER
Architecture: iphoneos-arm64e
Depends: mobilesubstrate | ellekit, preferenceloader, firmware (>= 14.0)
Description: 底部角落上滑返回上一级，含灵敏度与触发区域设置
Maintainer: Doubao
Author: Doubao
Section: Tweaks
EOF

# 打包 data 与 control（macOS tar，仅归档，格式交给 Linux 重打包）
cd "$STAGE"
tar -czf control.tar.gz DEBIAN
rm -rf DEBIAN
find . -type f -print0 | xargs -0 tar -czf data.tar.gz

cd "$ROOT"
printf '2.0\n' > debian-binary
cp debian-binary "$STAGE/debian-binary"
mv "$STAGE/control.tar.gz" .
mv "$STAGE/data.tar.gz" .

DEB="SwipeBack_${VER}_Bkey-macOS.deb"
rm -f "$DEB"
ar rcs "$DEB" debian-binary control.tar.gz data.tar.gz
echo ">>> built $DEB"
ls -la "$DEB"
