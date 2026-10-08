#!/bin/bash
# ============================================================================
#  上滑返回 —— macOS 云端构建脚本（GitHub Actions 内执行）
#  三个独立构建（App层 / 系统层 / 设置bundle）-> 收集产物 -> 补 substrate 依赖
#  -> 组装 deb 文件树 -> 打出 deb（格式不完美没关系，Linux 侧会干净重打包）
# ============================================================================
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"

# ---- 1. 准备 theos ----
if [ ! -d "$HOME/theos" ]; then
    echo ">>> installing theos..."
    # --recursive 会把全部子模块（dm.pl/include/lib/logos 等）一并克隆，
    # 新版 theos 已无根目录 ./bootstrap，无需再执行，直接可用。
    git clone --recursive --depth 1 https://github.com/theos/theos.git "$HOME/theos"
    export THEOS="$HOME/theos"
else
    export THEOS="$HOME/theos"
fi

# ---- 2. 编译（三个独立构建，避免子目录）----
echo ">>> make app..."
make -f Makefile.app
echo ">>> make sb..."
make -f Makefile.sb
echo ">>> make prefs..."
# 诊断：确认 SDK 私有框架里是否存在 Preferences
SDKPATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo '')"
echo ">>> SDKPATH=$SDKPATH"
if [ -n "$SDKPATH" ]; then
    ls "$SDKPATH/System/Library/PrivateFrameworks" 2>/dev/null | grep -i '^Preferences' && echo ">>> Preferences framework PRESENT" || echo ">>> Preferences framework MISSING from SDK"
fi
make -f Makefile.prefs

OBJ="$ROOT/.theos/obj/debug/arm64e"

# ---- 3. 组装文件树 ----
STAGE="$ROOT/stage"
rm -rf "$STAGE"
DL="$STAGE/Library/MobileSubstrate/DynamicLibraries"
PB="$STAGE/Library/PreferenceBundles/SwipeBackPrefs.bundle"
PL="$STAGE/Library/PreferenceLoader/Preferences"
mkdir -p "$DL" "$PB" "$PL"

cp "$OBJ/SwipeBackApp.dylib" "$DL/"
cp "$OBJ/SwipeBackSB.dylib"   "$DL/"
cp SwipeBackApp.plist  "$DL/SwipeBackApp.plist"
cp SwipeBackSB.plist   "$DL/SwipeBackSB.plist"
cp "$OBJ/SwipeBackPrefs.bundle/SwipeBackPrefs" "$PB/SwipeBackPrefs"
# 用我们自己的 Info.plist 覆盖 theos 生成的，保证 NSPrincipalClass 正确
cp SwipeBackPrefs-Info.plist "$PB/Info.plist"
cp Root.plist "$PB/Root.plist"
cp SwipeBackPrefs.plist "$PL/SwipeBackPrefs.plist"

# ---- 4. 把 substrate 依赖改成 .jbroot ----
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

# ---- 5. 打 deb ----
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

cd "$STAGE"
tar -czf control.tar.gz DEBIAN
rm -rf DEBIAN
find . -type f -print0 | xargs -0 tar -czf data.tar.gz

cd "$ROOT"
printf '2.0\n' > debian-binary
mv "$STAGE/control.tar.gz" .
mv "$STAGE/data.tar.gz" .

DEB="SwipeBack_${VER}_Bkey-macOS.deb"
rm -f "$DEB"
ar rcs "$DEB" debian-binary control.tar.gz data.tar.gz
echo ">>> built $DEB"
ls -la "$DEB"
