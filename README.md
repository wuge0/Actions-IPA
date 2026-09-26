# 无 Mac 构建 Godot iOS 版（TrollStore / 越狱设备自装）

适用条件：自己开发的游戏、装到自己的 iOS 15 设备上、设备已越狱并装有 TrollStore、手头没有 Mac。

核心思路：**TrollStore 能永久重签任意 IPA**，所以整条链路上最麻烦的"证书 + 描述文件 + 7 天续签"全部可以跳过，只剩"编译出 iOS 可执行文件"这一个硬需求——用 GitHub Actions 的 macOS runner 解决。

---

## ⚠️ 第一步（最关键）：iOS 15 必须改用 Compatibility 渲染器

Godot 4.7 的原生 iOS 导出最低支持 iOS 15.0，但**仅限 Compatibility 渲染器**；默认的 Mobile（Metal）渲染器要求 iOS 16+。不改的话装上会直接黑屏或闪退。

在 Godot 编辑器里：

```
项目 → 项目设置 → Rendering → Renderer
  ├─ Mobile Rendering Method   →  gl_compatibility
  └─ Web Rendering Method      →  gl_compatibility（可选）
```

代价是没有 Vulkan/Metal 的高级特性（SDFGI、VoxelGI、部分后处理），2D 游戏和中低强度 3D 完全够用。

---

## export_presets.cfg 参考

同目录下的 **`export_presets.cfg`** 是可直接复制到项目根目录（与 `project.godot` 同级）的最小可用版，只需改里面的 `MyGame` 和 `com.yourname.mygame`。

> 它是**最小版**：只写了必需字段，故意不写全。Godot 加载 preset 时缺失的 option 会走默认值，比手写一整套字段更不容易因版本差异报错。复制进去后在编辑器里打开一次「项目 → 导出」，Godot 会自动补全剩余字段并回写文件。
>
> 若项目里已有 `export_presets.cfg`，别直接覆盖——把 `[preset.0]` 改成 `[preset.1]` 追加到文件末尾。

想手抄的话，关键字段如下。在 Godot 里 `项目 → 导出 → 添加 → iOS` 建好 preset，名字保持默认的 **iOS**（workflow 里按这个名字找）：

```ini
[preset.0]

name="iOS"
platform="iOS"
runnable=true
export_filter="all_resources"
export_path="build/MyGame.xcodeproj"   # 与 workflow 的 project_name 对应
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

application/name="MyGame"
application/bundle_identifier="com.yourname.mygame"   # 反写域名，随便填，自装不校验
application/app_store_team_id=""                      # 留空即可，我们不走 App Store
application/min_ios_version="15.0"                    # ← 必须
application/targeted_device_family=2                  # 1=iPhone, 2=Universal
application/icon_interpolation=4
architectures/arm64=true
```

`bundle_identifier` 自己玩的话随便编一个，TrollStore 不校验唯一性。

---

## 使用流程

1. 把 Godot 项目推到 GitHub 仓库（**公开仓库的 macOS runner 完全免费**；私有仓库每月 2000–3000 分钟，但 macOS 按 10 倍计，实际只有 200–300 分钟，构建一次约耗 100–200 分钟 —— 所以下面"只构建一次"的技巧很重要）。
2. 把 `build-ios.yml` 放到仓库的 `.github/workflows/` 下。
3. GitHub 仓库页面 → **Actions** → 选 `Build Godot iOS IPA (unsigned)` → **Run workflow** → 填 Godot 版本、工程名、最低 iOS 版本 → 运行。
4. 跑完在 Artifacts 里下载 `MyGame-ipa.zip`，解压得到 `.ipa`。
5. 传到手机上，用 **TrollStore 打开安装**。永久有效，不会 7 天过期。

Godot 版本号必须和你本地编辑器**完全一致**（如本地是 4.7.2 就填 `4.7.2`），模板不匹配会导出失败。

---

## 省 CI 时长：只构建一次，之后只换 pck

这是整套方案里最实用的一招。Godot 的 iOS app 结构是这样的：

```
Payload/MyGame.app/
├── MyGame          ← 引擎二进制，改游戏不会变
├── MyGame.pck      ← 你的全部游戏数据（场景/脚本/资源）
└── Info.plist
```

引擎二进制和你的游戏内容是分离的。所以**只需要用 CI 构建一次"空壳 IPA"**，之后每次改游戏：

1. 本地 Godot 编辑器：`项目 → 导出 → Export PCK/ZIP`，导出 `MyGame.pck`
2. 解压 IPA → 替换 `Payload/MyGame.app/MyGame.pck` → 重新打包：
   ```bash
   mkdir -p Payload && cp -R MyGame.app Payload/
   zip -qry MyGame.ipa Payload
   ```
3. 丢给 TrollStore 重装

完全不消耗 GitHub Actions 分钟数。**只有改动了 `project.godot` 里的项目设置、或升级了 Godot 版本，才需要重新跑一次 CI。**

> 如果改的是代码逻辑而非项目设置，换 pck 就够了。GDScript 是随 pck 走的，不需要重编译引擎。

---

## 越狱设备的额外便利：直接替换已装的 pck

既然设备已越狱，连重装都省了。用 Filza 或 SSH 进设备，找到已安装 app 的 bundle 目录（`/var/containers/Bundle/Application/<UUID>/MyGame.app/`），把新的 `MyGame.pck` 覆盖进去即可。AppSync Unified 会跳过校验，下次打开就是新版本。

前提：越狱后装了 **AppSync Unified**（源 `cydia.akemi.ai`）。没装的话覆盖后会因签名校验失败而闪退。

---

## 常见问题

| 现象 | 原因 / 解法 |
|---|---|
| `The iOS 15.0 deployment target is not supported` | runner 的 Xcode 太新。改 `runs-on: macos-13`，或在 workflow 里 `sudo xcode-select -s /Applications/Xcode_15.x.app` |
| 导出时提示模板缺失 / 版本不匹配 | 本地 Godot 版本与 workflow 里 `godot_version` 不一致，核对一下 |
| 安装后打开闪退 | 99% 是渲染器没改成 Compatibility，回看第一节 |
| TrollStore 装不上 / 提示不支持 | 确认系统版本在 iOS 14.0–16.6.1 区间内；iOS 17.0.1+ 该漏洞已修补 |
| xcodebuild 报签名相关错误 | workflow 已用 `CODE_SIGNING_ALLOWED=NO` 全套关掉，若仍报错检查 preset 里是否残留 team id |

---

## 其他无 Mac 备选

| 方案 | 成本 | 备注 |
|---|---|---|
| GitHub Actions macOS runner | 公开仓库免费 | 本方案；私有仓库分钟数紧张 |
| 云 Mac 按时租用（MacinCloud / MacStadium） | 约 $1–2/小时 | 首次配置麻烦，之后可交互调试，适合长期用 |
| 借/远程一台 Mac 做最后一步 | ¥0 | 最快，但要欠人情 |
| Web 导出（HTML5） | ¥0 | 完全绕开 iOS 工具链，Safari 直接玩；要求 iOS 16+（WASM SIMD），iOS 15 上会卡在加载页 |

最后一条值得单独说：**如果你的游戏是 2D 且不强求原生体验，Web 导出其实比折腾 IPA 省事得多**。但 iOS 15 不支持 SIMD，这条路在你的设备上走不通——所以还是按上面的方案来。

---

## 合规提醒

以上流程用于**把你自己开发的游戏装到你自己的设备**上，是正当的开发者自测行为。请勿用它安装或分发他人的付费应用/破解包。
