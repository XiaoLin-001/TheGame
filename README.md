# 潮與線 Tide & Line

塔防 × 節點連線式自動化。**你的生產線就是你的防線**——在敵潮抵達之前，決定這一分鐘是擴產還是築防。

Godot 4.7（GDScript，`gl_compatibility` 渲染）。Windows 先行，從第一批起就以手機移植為前提設計。
目前版本與進度：[`godot/scripts/core/GameState.gd`](godot/scripts/core/GameState.gd) 的 `VERSION`、[`CHANGELOG.md`](CHANGELOG.md)。

## 三十秒上手

```bash
python dev/setup.py        # 檢查並補齊：Godot 4.7、Windows 匯出範本、匯出設定、專案匯入
dev\play.bat               # 直接從原始碼樹開遊戲
```

`python dev/setup.py --check` 只檢查不下載。缺的東西全部來自
[godotengine/godot 的官方 release](https://github.com/godotengine/godot/releases)，約 1 GB（匯出範本佔大宗）。

## 改完程式要跑什麼

```bash
python qa/check.py lint            # 靜態地雷掃描（不需要 Godot，1 秒）
python qa/check.py tests --fast    # 22 支 headless 測試，跳過最慢的 campaign（約 2 分鐘）
python qa/check.py tests           # 全部（約 5 分鐘）
python qa/check.py click           # 輸入層自檢：用合成滑鼠事件真的點畫面（會開視窗，約 1 分鐘）
python qa/check.py all             # lint ＋ 文案稽核 ＋ 測試 ＋ clicktest
python qa/check.py perf --runs 3   # 渲染幀時間（戰役 1／5／10 關活的模擬 ＋ 壓力場景；關 vsync，取中位數）
```

**搬動程式碼的批次**（重構、改檔案結構）另外要跑截圖比對——同一台機器上截圖是確定性的，所以要求 **0 像素差**：

```bash
python qa/check.py shots OUT_DIR                       # 拍 32 張基準圖（先在改動前拍一次）
python qa/check.py shots NEW_DIR --against OUT_DIR     # 改完再拍，逐像素比對
```

匯出 exe（每批收尾都要，並在 exe 上再跑一次 clicktest——匯出會打包資源，原始碼樹綠燈不代表 exe 沒缺檔）：

```bash
dev\export.bat             # → build\TideAndLine.exe
```

詳細規範與每個測試鉤子（`TL_*` 環境變數）見 [`CLAUDE.md`](CLAUDE.md)「跑與測」。

## 程式碼地圖

```
godot/
├── data/                  資料表 ＋ 讀它的純函式（NodeDefs、Enemies、Maps、Campaign、Tech、…）：加內容是加一列
├── scripts/
│   ├── core/              autoload：Hooks、Rng、AudioBus、SaveService、GameState ＋ Env
│   ├── sim/               ★ 純函式模擬（零副作用、零系統 RNG）：FlowNetwork、Combat、Tide、Build、MapGen、…
│   ├── game/              局的狀態與每 tick 解算：SessionState、BattleController、BuildController
│   ├── meta/              局外系統（有狀態轉移）：TycoonSim
│   ├── render/            共用美術 token（Palette、Motion、Shapes）
│   │   └── 2d/            2D 專用的幾何與繪製（Glyphs、Foes、Terrain、TitleBackdrop）
│   ├── ui/                UiKit（字型、主題、共用 helper）
│   └── screens/           各畫面
│       ├── Battle.gd      局內畫面：指揮者（局的建立、節拍、輸入、HUD 版面）
│       └── battle/        局內畫面的模組：Stage（2D→3D 的接縫）、Overlay2D、Feedback、SelfTest、hud/*
├── tests/                 22 支 headless 測試 ＋ 輔助（含 fuzz：亂序操作 × 多張地圖；render_cache：畫面快取的失效規則；stage3d：舞台契約）
└── assets/audio/          程序生成的音源（assetgen/gen_audio.py）
docs/                      概念、GDD、美術、技術、生產計畫、QA；60 程式碼地圖、70 3D 轉換準備
qa/                        check.py（統一入口）、gd_lint.py（靜態掃描）、gd_graph.py（依賴圖）、文案稽核
dev/                       setup.py、play.bat、export.bat
```

- 想知道「**砍掉哪段程式碼遊戲會跑不起來**」：[`docs/60_CODE_MAP.md`](docs/60_CODE_MAP.md)
  （`python qa/gd_graph.py --cut FILE` 可以現場算）
- 想知道「**怎麼從 2D 轉 3D**」：[`docs/70_3D_MIGRATION.md`](docs/70_3D_MIGRATION.md)

## 文件權威順序

衝突時**上位者為準**，並在當批修正下位文件：

```
00_CONCEPT（願景與紅線） → 10_GDD（設計唯一權威） → 20_ART_DIRECTION（視覺／動效／音訊）
                                       ├→ 30_TECH_DESIGN（架構／存檔／測試鉤子／效能）
                                       ├→ 40_PRODUCTION_PLAN（里程碑／批次／風險）
                                       └→ 50_QA_PLAN（測試策略／bug／回歸）
```

**設計改動先改文件，再改程式碼。** 數值一律寫在 `10_GDD.md` §7，不在程式碼裡即興發明。
`CLAUDE.md` 列了**鎖定的設計**（核心取捨、耗能模型、能量是流率、優先權按類型……）——
要改先問，不要擅自動。

## 三條不能破的工程慣例

1. **`scripts/sim/` 必須是純函式、零副作用、零系統 RNG**——每日挑戰的公平性、重播、可驗證榜單都踩在這上面。
   禁用 `randf()`／`randi()`／`Time.get_ticks_*()`，一律用注入的 seeded `Rng`。
2. **色值只在 `scripts/render/Palette.gd`**；中文 UI 一律走 `UiKit` 的 `SystemFont`（Godot 預設字型沒有 CJK）。
3. **有任何 `TL_*` 測試鉤子時存檔不落地**（`Env.any_hook()`）。新增鉤子必須同步列進 `Env.HOOKS`
   ——`qa/gd_lint.py` 會檢查。
