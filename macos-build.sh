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
# 双架构编译，用 DEBUG=0 关闭 dSYM，避免 theos lipo 合并 universal 时与 dSYM 冲突
make -f Makefile.app DEBUG=0
echo ">>> make sb..."
make -f Makefile.sb DEBUG=0
echo ">>> make prefs..."
# 诊断：确认 SDK 私有框架里是否存在 Preferences
SDKPATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo '')"
echo ">>> SDKPATH=$SDKPATH"
if [ -n "$SDKPATH" ]; then
    ls "$SDKPATH/System/Library/PrivateFrameworks" 2>/dev/null | grep -i '^Preferences' && echo ">>> Preferences framework PRESENT" || echo ">>> Preferences framework MISSING from SDK"
fi
make -f Makefile.prefs DEBUG=0

# release 模式产物在 .theos/obj 下（collect_one 用 find 定位，兼容 debug/release）
OBJ_BASE="$ROOT/.theos/obj"

# ---- 3. 组装文件树 ----
STAGE="$ROOT/stage"
rm -rf "$STAGE"
DL="$STAGE/Library/MobileSubstrate/DynamicLibraries"
PB="$STAGE/Library/PreferenceBundles/SwipeBackPrefs.bundle"
PL="$STAGE/Library/PreferenceLoader/Preferences"
mkdir -p "$DL" "$PB" "$PL"

# 双架构编译后 theos 可能产出单 universal 或分 arch 多个文件，统一收集
collect_one() {
    local name="$1" out="$2"
    # 优先取 theos 合并好的 universal（.theos/obj 根目录），避免再 lipo 时与各 arch 副本冲突
    if [ -f "$OBJ_BASE/$name" ]; then
        cp "$OBJ_BASE/$name" "$out"; echo ">>> collected universal $name -> $out"; return
    fi
    local files n
    files=$(find "$OBJ_BASE" -name "$name" -type f 2>/dev/null)
    if [ -z "$files" ]; then echo ">>> ERROR: missing $name"; exit 1; fi
    n=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
    if [ "$n" = "1" ]; then
        cp "$files" "$out"
    else
        lipo -create $files -output "$out"
    fi
    echo ">>> collected $name -> $out"
}
collect_one SwipeBackApp.dylib "$DL/SwipeBackApp.dylib"
collect_one SwipeBackSB.dylib "$DL/SwipeBackSB.dylib"
collect_one SwipeBackPrefs "$PB/SwipeBackPrefs"
cp SwipeBackApp.plist  "$DL/SwipeBackApp.plist"
cp SwipeBackSB.plist   "$DL/SwipeBackSB.plist"
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

# ---- 5. 打 tree 包（用 GNU tar；deb 在 Linux 侧干净重打包，避开 macOS tar/ar 问题）----
echo ">>> packaging tree..."
VER="0.2.87"
# 确认文件树非空
if ! find "$STAGE" -type f | grep -q .; then
    echo ">>> ERROR: stage tree is EMPTY"; exit 1
fi
# 用 coreutils 的 gtar 打包（macOS BSD tar 不可靠）
if command -v gtar >/dev/null 2>&1; then
    TAR=gtar
else
    TAR=tar
fi
"$TAR" -czf "SwipeBack_${VER}_tree.tar.gz" -C "$STAGE" .
echo ">>> built SwipeBack_${VER}_tree.tar.gz"
ls -la "SwipeBack_${VER}_tree.tar.gz"
