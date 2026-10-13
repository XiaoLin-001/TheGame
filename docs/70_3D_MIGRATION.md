# 《潮與線》2D → 3D 轉換準備

> 狀態：**準備完成（B3.14），轉換本身尚未開始。** 分支 `3D-project`。
> 上位文件：`00_CONCEPT.md`、`10_GDD.md`、`20_ART_DIRECTION.md`（現行是 **2D 平面向量語言**，轉 3D 要改寫，見 §1 D2）。
> 配套：`60_CODE_MAP.md`（哪些程式碼與維度無關）。

---

## 0. 一句話

**模擬、資料、存檔、HUD、輸入邏輯全部與維度無關**（約 84% 的程式碼，且都有測試鎖住）。
只有「**舞台**」是 2D 專屬：`Stage2D`（約 1400 行）＋ `render/2d/` 的四支美術生成器（約 1400 行）。
B3.14 把這兩塊從 5316 行的 `Battle.gd` 裡切了出來，並在它們前面立了一份**契約**（`screens/battle/Stage.gd`）：
換成 3D＝**照契約另寫一個 `Stage3D.gd`**，局內畫面與全部 HUD 不必動。

驗證過的事實（不是推測）：重構前後 **32 張截圖逐像素 0 差**、11 條 clicktest 全過、20 支 headless 測試全過
——也就是說這個接縫是真的接縫，不是紙上畫的。

---

## 1. 要使用者拍板的決定

每一條：**是什麼 · 影響 · 建議**。沒有拍板之前，3D 的實作不該開始。

| # | 決定 | 影響 | 建議 |
|---|---|---|---|
| **D1** | **「3D」的範圍** | A：**3D 渲染的格子地圖**——玩法、操作、關卡、模擬一個字不改，只換呈現（建築與敵人變模型、相機有俯角）。B：**真 3D 玩法**（高度、自由視角、3D 路徑）——設計全部重來，鎖定的設計（一屏可見、橋、walk-by）都要重審。 | **A**。B 等於另一款遊戲，且會動到 `CLAUDE.md` 鎖定的設計。 |
| **D2** | **美術管線：維持「零素材、程序生成」，還是引入 glTF 模型** | 現行鎖定「所有視覺以 `_draw()` 與 shader 程序繪製，不使用外部素材」（`20_ART_DIRECTION.md` §6）：授權乾淨、體積小、改一處全同步。3D 若走程序網格（`ArrayMesh`／`CSG`）可以維持這條；走 glTF 則要有美術資產來源與授權。 | **先維持程序生成**（低多邊形＋平面著色，和現有的幾何語言一脈相承），首批只做 13 種節點＋6 種敵人。需要時再引入素材，不要一開始就改管線。 |
| **D3** | **相機** | 自由軌道相機會讓「導管線寬／顏色／徽章」這套視覺編碼失真（近大遠小），而全案的可讀性驗收（R-3，`TL_NAKED`）就押在它上面。 | **固定俯角（約 50–60°）、正交或極小 FOV 的透視、只開縮放與平移**，先不開旋轉。旋轉可以之後加（契約的 `zoom_by`／`pan_by` 不變）。 |
| **D4** | **「戰役關卡一屏可見」在 3D 下怎麼解讀** | 鎖定的設計（`CLAUDE.md` 地圖尺度）。2D 靠「固定框架＋進場自動 fit」保證；3D 沒有 `fit`，要改成「相機自動框住整張圖」。 | **維持鎖定**：進場相機自動框住整張圖（`Stage.reset_view()` 的 3D 版）。`campaign_test` 那條「fit 後填滿框架」的斷言要換成相機版。 |
| **D5** | **保不保留 2D 舞台** | 兩個舞台並存＝兩份繪圖要維護；但 2D 版是**低配機、手機、無障礙**的退路，也是回歸比對的基準。 | **轉換期並存**（設定裡一顆開關）；3D 穩定後再決定要不要留。契約讓兩者並存幾乎零成本。 |
| **D6** | **效能與平台底線** | 現行壓力情境（547 節點、2045 導管、200 敵人）渲染約 23 FPS（RG-8，已知）。3D 的導管若逐條一個 `MeshInstance3D` 會更糟；手機移植的門檻也會更高。保持 `gl_compatibility`。 | **導管、節點、敵人一律走 `MultiMesh`（一種一個 draw call）**，流動珠用 shader 的 UV 捲動而不是逐珠物件。**效能預算要在 B4.0 就量，不要留到最後**（見 §6）。 |
| **D7** | **回歸比對怎麼辦** | 2D 截圖「同機器逐像素相同」；3D 的光柵化在不同 GPU／驅動上不保證位元相同。 | 同機器仍可逐像素；跨機器改用**容忍度比對**（`qa/check.py shots` 的 `_compare` 加一個閾值參數）。 |

---

## 2. 現況：什麼與維度無關

| 層 | 行數（約） | 與維度的關係 | 3D 時 |
|---|---:|---|---|
| `data/`、`scripts/sim/`、`scripts/meta/`、`scripts/game/` | 7,500 | **完全無關**（純函式；格座標是 `Vector2i`） | 不動 |
| `scripts/core/`（autoload、存檔） | 1,100 | 無關 | 不動 |
| `scripts/screens/`（除 `Battle`）、`ui/UiKit` | 3,500 | 無關（2D `Control`） | 不動 |
| `screens/Battle.gd`（指揮者） | 700 | **只透過 `Stage` 契約**碰舞台 | 不動 |
| `screens/battle/hud/*`（11 個面板）、`Overlay2D`、`Feedback` | 2,600 | 無關（螢幕座標的 `Control`；問視野一律走 `stage.*`） | 不動 |
| **`screens/battle/Stage2D.gd`** | **1,420** | **2D 專屬** | **重寫成 `Stage3D.gd`** |
| **`render/2d/`**：`Glyphs`、`Foes`、`Terrain`、`TitleBackdrop` | **1,400** | **2D 專屬**（輸出 2D 多邊形與線） | 寫 3D 網格生成器 |
| `render/`：`Palette`、`Motion`、`Shapes` | 550 | 色值與時長階無關；`Shapes` 裡的繪圖 helper 是 2D 的，`GRID`／`fit_zoom` 不是 | 色值與時長階沿用 |
| `screens/battle/SelfTest.gd` | 1,400 | 自檢大多走 HUD（不受影響）；少數探針讀 `Stage2D` 內部（`no_glyph`、`pan` 夾限） | 那幾條改成問契約 |

---

## 3. 接縫：`Stage.gd` 契約

`screens/battle/Stage.gd` 是一個 `Control` 基底類別，**每一個函式都是空實作加文件**——它就是 3D 舞台的待辦清單：

| 類別 | 契約 | 2D 的做法 | 3D 的做法（建議） |
|---|---|---|---|
| 投影／拾取 | `cell_at(螢幕)`、`point_at(螢幕)`、`center(格)`、`to_screen(地圖座標)`、`in_map(格)` | `(pos − map_origin) / zoom` | **射線與地平面（y=0）求交**；`to_screen` ＝ `camera.unproject_position()` |
| 視野 | `reset_view()`、`zoom_by()`、`pan_to()`、`pan_by()`、`center_view_on()`、`tick_view()` | `zoom`／`pan` 兩個標量、`draw_set_transform` | 相機高度／目標點；`reset_view` ＝ 自動框住整張圖（D4） |
| 讀值 | `zoom`、`fit`、`pan`、`pan_goal`、`FRAME`、`ZOOM_STEP` | 同左 | `zoom/fit` 比值給 HUD 的「全景 100%」；`FRAME` ＝ `SubViewportContainer` 的矩形 |
| 視野查詢 | `view_world_rect()`、`oversized()` | 直接算 | 相機視錐與地面交集的外接矩形 |
| 每幀推導 | `engaged`、`threat`（HUD 與小地圖會讀） | `_draw()` 開頭用 `Combat.engaged()` 算 | **同一份算式，搬到 `_process`**——這兩個與畫法無關 |
| 訊號 | `view_moved` | 視野變了就發 | 同 |

三個約定（寫在契約檔頭）：

1. **座標**：「格」＝ `Vector2i`（模擬層唯一座標）；「地圖座標」＝ 格 × `Shapes.GRID`（像素）；「螢幕座標」＝ `Control` 的全域像素。3D 世界座標建議 `Vector3(格.x, 高度, 格.y)`（1 格 ＝ 1 單位）。
2. **舞台只讀 `s`**（`SessionState`），不改局面、不擁有規則。
3. **它是滿版 `Control`、`mouse_filter = IGNORE`**——點擊一律落到 `Battle._gui_input`（B0.7.2 的教訓：命中區與繪圖是兩件事）。3D 版把一個 `SubViewportContainer`（同樣 IGNORE）放在裡面。

**`Battle._build_modules()` 目前寫死 `Stage2D.new()`**——轉換時改成讀設定（D5），這是主畫面裡**唯一**需要知道「哪一種舞台」的一行。

---

## 4. `Stage2D` 的每一層 → 3D 對應

Stage2D 的 `_draw()` 依序畫下面這些層（都讀 `s`，不改 `s`）。3D 版每一層一個節點，**由資料驅動重建／更新，不逐幀 new**。

| 2D 層（`Stage2D._draw_*`） | 內容 | 3D 做法（建議） |
|---|---|---|
| 地貌（`terrain_layer`＋`Terrain.build()`） | 八種地貌：底色＋裝飾（B3.13），**只在換圖時重畫** | 地面一塊 `MeshInstance3D`（程序貼圖／頂點色）＋裝飾 `MultiMesh`。`Terrain.build()` 的零件是純資料（位置、種類、種子），**可以直接當 3D 的輸入** |
| 網格線 | `Shapes.draw_grid` | 地面 shader 的格線 |
| `_draw_path` | 侵蝕暈（＝walk-by 傷害半徑）＋路徑帶＋來襲箭羽＋橋 | 地面上的 decal／貼花網格；**暈的外緣要保持「走格線、可數格」**（`20_ART_DIRECTION.md` §1.6：規則層要讓玩家用格子數邊界） |
| `_draw_ore_cells`、`_draw_fields` | 礦點、光環／射程場 | 地面圓環 decal |
| `_draw_conduits` | 導管：**線寬＝流量、顏色＝資源／飢餓、流動珠＝方向**（R-3 的核心編碼） | 一條導管一個管狀網格實例（`MultiMesh`），**寬度與顏色走 per-instance 參數**；珠子用 shader UV 捲動。**這是可讀性風險最大的一層**（D3） |
| `_draw_nodes` | 13 種節點，每種有自己的體積語言（`Glyphs.build_for()`）＋三態徽章＋交戰高亮 | 每種節點一個程序網格（低多邊形）＋徽章用 `Sprite3D`／billboard。`Glyphs` 的規格表（哪種形狀、幾何體積）可以直接當 3D 網格的設計稿 |
| `_draw_enemies` | 六隻敵人（`Foes.build()`，由機制欄位推導） | 六種程序網格；位置用 `Tide.pos_of()`（模擬層給的連續座標，**不要在 3D 重算**） |
| `_draw_shots`、`_draw_bursts`、`_draw_shields`、`_draw_ripple` | 開火兩端、碎片爆、屏障擋格、開打漣漪（0.2 秒、十幾像素的東西） | 短壽命的 `GPUParticles3D`／immediate mesh。**`Motion.reduce` 時一律不生成**（`reduce_motion` 的承諾，§4.4） |
| `_draw_selection`、`_draw_hover`、`_draw_connect_guides` | 選取框、擺放預覽（畫那隻角色本人）、拉線導引 | 外框 shader／decal；擺放預覽用同一套節點網格半透明 |
| `_draw_frame_matte` | 把超出框架的地圖遮掉 | **不需要**——`SubViewportContainer` 自己就是框架 |
| 階段色調 | 戰鬥期整層淡橙、準備期淡青（`10_GDD.md` §6.2 硬性要求 4） | 後處理或地面 tint |

**不要重新發明的東西**：`Glyphs`／`Foes`／`Terrain` 的輸出都是**純資料的零件清單**（位置、種類、色值 token），2D 的 `paint()` 只是「怎麼把零件畫成多邊形」。3D 版應該**吃同一份零件清單**、換一個「怎麼把零件變成網格」，而不是重新從 `NodeDefs` 推一遍——否則兩套會漂。

---

## 5. 輸入與相機

- **拾取**：`cell_at()`／`point_at()` 是 `Battle._gui_input` 唯一的座標來源。導管命中靠 `point_at()`（格為單位的浮點座標）＋ `WIRE_PICK = 0.3`；3D 的透視會讓這條帶在螢幕上的寬度隨距離變化——D3 選正交／極小 FOV 就避開這個問題。
- **平移**：中鍵拖曳走 `stage.pan_by()`（契約）。觸控沒有中鍵，**手機移植要補雙指手勢**（風險已登記在 `40_PRODUCTION_PLAN.md`，與 2D 無關）。
- **觸控命中 ≥ 44×44 px**：HUD 已全部遵守（`UiKit.touchable`）；3D 地圖上的點擊目標（一格 32px × zoom）仍是「放大操作」解，與 2D 同。
- **相機緩動**：`tick_view(delta)` 用 `1 − exp(−k·dt)`（與幀率無關）；`reduce_motion` 時一律直接到位。

---

## 6. 效能預算（B4.0 就要量）

| 情境 | 2D 現況（`TL_STRESS=1`，渲染） | 3D 目標 |
|---|---|---|
| 一屏戰役關（約 20 節點、30 導管、10 敵人） | 遠高於 60 FPS | ≥ 60 FPS（桌面）、≥ 45 FPS（底線） |
| 壓力情境（547 節點、2045 導管、200 敵人） | 約 23 FPS（RG-8，**已知未解**） | 不得比 2D 差；`MultiMesh` 應該更好 |

量法不變：`TL_STRESS=1`（模擬凍結、只量渲染）。**3D 版也要吃這個鉤子**——它是 `Hooks.stress`，與舞台無關。

---

## 7. 測試與驗收

| 項目 | 3D 時 |
|---|---|
| 20 支 headless 測試 | **完全不受影響**（沒有一支載入舞台） |
| `determinism_test`／`perf_test` | 不受影響（`sim/` 不碰渲染） |
| 10 條 clicktest | 走 HUD ＋ 合成滑鼠事件 → **原封不動可以跑**（它們問的是 `stage.cell_at`／`to_screen`，不是 2D 專屬）。例外：`SelfTest` 裡讀 `Stage2D` 內部的幾條探針（見 §2 最後一列） |
| 截圖矩陣（32 張） | 2D 版不變；3D 版另拍一份基準。HUD 部分兩者應相同 |
| `TL_NAKED`（可讀性驗收：隱藏數值、只看線寬／顏色／徽章） | **3D 版的驗收仍用它**——而且比 2D 更重要（D3） |
| 「陌生人看得懂瓶頸在哪」（R-14） | 3D 改了視覺編碼的載體，**要重新拉真人**——agent 不能代判（`50_QA_PLAN.md` §0.1） |

---

## 8. 建議的分批（M4 之前，不佔現有 M3 批次）

| 批次 | 內容 | DoD |
|---|---|---|
| **B4.0 脊椎** | `Stage3D.gd`：地面＋路徑＋節點（方塊）＋敵人（球）＋相機（D3）＋拾取。設定開關 `stage = 3d`（預設 2D）。 | HUD 與輸入**不改一行**就能在 3D 舞台上蓋東西、拉線、選取；clicktest 全過；`TL_STRESS` 有數字 |
| **B4.1 導管** | 管狀網格＋ per-instance 寬度／顏色＋流動珠 shader | `TL_NAKED` 截圖裡瓶頸仍然看得出（人判） |
| **B4.2 節點與敵人** | 13＋6 種程序網格，吃 `Glyphs`／`Foes` 的零件清單 | 每種節點都有網格（`no_glyph` 探針的 3D 版） |
| **B4.3 特效與地貌** | 開火兩端、碎片爆、屏障；八種地貌 | `reduce_motion` 全覆蓋 |
| **B4.4 效能** | `MultiMesh` 化、壓力情境 | 達到 §6 的目標 |
| **B4.5 美術** | 光照、材質、色調；改寫 `20_ART_DIRECTION.md` 的 3D 章節 | 使用者判美術（agent 不判好不好看） |

---

## 9. 風險

| # | 風險 | 對策 |
|---|---|---|
| R3D-1 | 透視讓導管線寬編碼失真，全案可讀性驗收（R-3）失效 | D3：正交／小 FOV；B4.1 的 DoD 由人判 |
| R3D-2 | 兩個舞台並存，兩份繪圖漂移 | 零件清單共用（§4 最後一段）；契約檔是唯一介面 |
| R3D-3 | `Stage2D` 與 `SelfTest` 有少數內部耦合（`no_glyph`、`pan` 夾限） | 轉換時把那幾條探針改成問契約；它們已經集中在 `SelfTest.gd` 一個檔 |
| R3D-4 | 3D 讓「程序生成、零素材」的優勢變成負擔（網格要自己寫） | D2：先低多邊形；`Glyphs` 的規格表當設計稿；真的不夠再引入素材 |
| R3D-5 | 渲染效能（RG-8 已經是 23 FPS） | B4.0 就量；`MultiMesh` |
