# zrk_calendar

一个用 Flutter + Drift 打造的本地离线个人日历。它面向 Ubuntu Linux 桌面端，主视图是清爽的中文月历：每个日期同时显示公历和农历，内置常见中外节日、2026 年中国官方休/班安排，并支持按日期记录待办、管理公历/农历生日和纪念日。所有个人数据都保存在本机 SQLite 数据库中，不需要登录，当前不连接云端，也不依赖运行时网络接口。

适合想要一个“轻一点、私有一点、能看农历和调休”的个人桌面日历的人。当前版本是第一版可运行实现，重点放在本地持久化、月视图、待办、生日纪念日规则和 JSON 导入导出。

## 主要特性

- 月视图展示公历日期、农历日期、节日、休/班标记和待办摘要。
- 右侧详情面板展示当天农历、节日、生日/纪念日和待办列表。
- 待办支持添加、编辑、删除、完成/取消完成。
- 生日/纪念日支持公历或农历每年重复，预留农历闰月策略。
- 生日/纪念日规则支持 JSON 导入导出。
- 使用 Drift + SQLite 本地保存数据，应用关闭后仍保留。
- 用户数据使用 UUID、软删除和同步预留字段，方便后续接入多端云同步。
- 官方假期和节日规则均为本地数据或本地规则。

## 运行

```bash
flutter pub get
flutter run -d linux
```

项目的 Linux CMake 配置会自动避开本机不完整的 GCC C++ 工具链路径。如果仍遇到 `clang++` 找不到 C++ 标准库头文件或 `-lstdc++`，可临时显式指定已安装的 GCC 开发路径：

```bash
CPLUS_INCLUDE_PATH=/usr/include/c++/11:/usr/include/x86_64-linux-gnu/c++/11 \
LIBRARY_PATH=/usr/lib/gcc/x86_64-linux-gnu/11 \
flutter build linux
```

## 验证

```bash
flutter analyze
flutter test
flutter build linux
```

## 关键目录

```text
lib/
├── app/                         # App 组装、主题、作用域
├── database/                    # Drift 数据库表与连接
├── features/
│   ├── calendar/                # 月视图、控制器、日期模型
│   ├── recurring_event/         # 生日/纪念日模型与 repository
│   └── todo/                    # 待办 repository
├── services/                    # 农历、节日、假期、导入导出、重复事件生成
│   └── sync/                    # 云同步接口与 Noop 空实现
└── shared/                      # 日期工具等共享代码
assets/data/holidays/            # 官方休班安排 JSON
assets/data/festivals/           # 节日规则和来源说明 JSON
test/                            # 单元测试
```

## 数据库表

当前 `schemaVersion = 2`。从 v1 升级到 v2 时，迁移会保留已有待办和生日/纪念日规则，为旧数据生成新的 UUID，并将旧数据标记为 `sync_status = pending`、`deleted_at = null`、`last_synced_at = null`。

`todo_items`

- `id`：UUID 字符串主键
- `title`：标题
- `date`：绑定的公历日期
- `is_completed`：是否完成
- `note`：备注
- `created_at` / `updated_at`：创建和更新时间
- `deleted_at`：软删除时间，默认 `null`
- `sync_status`：同步状态，当前可为 `pending`、`synced`、`failed`
- `last_synced_at`：最后同步成功时间，当前预留

`recurring_events`

- `id`：UUID 字符串主键
- `title`：标题
- `event_type`：`birthday` 或 `anniversary`
- `calendar_type`：`solar` 或 `lunar`
- `month` / `day`：规则月日
- `is_leap_month`：是否农历闰月
- `leap_month_policy`：`useNormalMonth` 或 `skipThisYear`
- `note`：备注
- `enabled`：是否启用
- `created_at` / `updated_at`：创建和更新时间
- `deleted_at`：软删除时间，默认 `null`
- `sync_status`：同步状态，当前可为 `pending`、`synced`、`failed`
- `last_synced_at`：最后同步成功时间，当前预留

新增、编辑、完成/取消完成、删除都会更新 `updated_at` 并将 `sync_status` 标记为 `pending`。删除不会物理移除记录，而是写入 `deleted_at`；默认查询和界面展示都会过滤软删除记录。

## 云同步准备状态

当前版本尚未接入真实云同步，但本地数据库已经改造为同步友好结构：

- 用户数据使用 UUID 主键，便于多端合并。
- 删除采用 `deleted_at` 软删除，方便未来把删除操作同步到云端。
- 本地变更会标记 `sync_status = pending`。
- 预留 `last_synced_at`。
- 预留 `SyncService` 接口和 `NoopSyncService` 空实现。
- 后续可接入 Supabase 等云端小数据库。

安全注意：

- `.env`、本地 SQLite 数据库、个人导入导出的 JSON 文件不应提交到 Git。
- Supabase 的 `service_role` key 未来绝不能写入 Flutter 客户端或 GitHub。
- Flutter 客户端未来只能使用 Supabase URL 和 publishable/anon key。
- 真正的安全边界依赖 Supabase RLS 规则，而不是把 key 藏在客户端代码里。

## JSON 导入导出

第一版仅导入/导出生日和纪念日规则，不导入待办。导入时会为每条规则生成新的本地 UUID，并标记为 `sync_status = pending`。导出仍是面向用户的规则备份格式，不是云同步协议；不会导出 `id`、`deleted_at`、`sync_status`、`last_synced_at` 等内部字段，也不会导出软删除记录。

Schema 要点：

- 顶层必须是对象。
- `schemaVersion` 当前为 `1`。
- `rules` 必须是数组。
- 每个规则必须包含 `title`、`eventType`、`calendarType`、`month`、`day`。
- `eventType`：`birthday` 或 `anniversary`。
- `calendarType`：`solar` 或 `lunar`。
- `isLeapMonth`：布尔值，公历事件必须为 `false` 或省略。
- `leapMonthPolicy`：`useNormalMonth` 或 `skipThisYear`。
- `enabled`：布尔值，可省略，默认启用。

示例：

```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "title": "妈妈生日",
      "eventType": "birthday",
      "calendarType": "solar",
      "month": 8,
      "day": 16,
      "isLeapMonth": false,
      "leapMonthPolicy": "useNormalMonth",
      "enabled": true,
      "note": "每年提醒"
    },
    {
      "title": "奶奶生日",
      "eventType": "birthday",
      "calendarType": "lunar",
      "month": 8,
      "day": 15,
      "isLeapMonth": false,
      "leapMonthPolicy": "useNormalMonth",
      "enabled": true
    }
  ]
}
```

## 官方假期数据

`assets/data/holidays/china_official_2026.json` 记录 2026 年中国官方放假和补班安排。来源为中国政府网发布的《国务院办公厅关于2026年部分节假日安排的通知》，国办发明电〔2025〕7号，发布日期 `2025-11-04`。

`assets/data/holidays/china_official_2027.json` 目前仅保留占位结构。截至 `2026-06-03`，尚未在中国政府网政策文件库检索到 2027 年国务院办公厅官方放假调休通知，因此不填充任何具体休/班日期，避免使用非官方预测数据。

注意：该 JSON 只表示官方“休/班”安排，不表示节日本身。节日本身由 `FestivalService` 的本地规则判断。

## 节日规则来源

`assets/data/festivals/festival_rules.json` 记录当前应用内置节日规则及来源网站，包含：

- 公历固定节日：元旦、情人节、劳动节、国庆节、万圣节、圣诞节。
- 星期规则节日：母亲节、父亲节、感恩节。
- 农历节日：春节、元宵节、端午节、七夕、中秋节、重阳节、除夕。
- 每条规则的来源网站、来源索引和 2026 年抽样核对日期。
- 2026 年中国官方休/班数据文件与来源映射。

已核对的主要来源包括中国政府网的《全国年节及纪念日放假办法》和 2026 年节假日安排通知、央视网“中国传统节日”专题、香港天文台公农历对照表、Encyclopaedia Britannica 对外国常见节日的条目，以及 USAGov 的美国节假日说明。应用运行时不访问这些网站；它们只作为仓库内可追溯的规则依据。

当前第一版没有实现跨年份清明节节气计算。2026 年清明节会通过 `china_official_2026.json` 显示官方休假安排；如果未来要把清明作为每年节日本身显示，需要增加节气计算或本地年度规则。

## 第三方依赖

- Flutter / Dart：应用框架与语言，BSD-3-Clause。
- drift / drift_dev：SQLite ORM 与代码生成，MIT。
- sqlite3_flutter_libs：随应用提供 SQLite 动态库，MIT。
- lunar：农历转换，本地离线使用，MIT。
- file_picker：JSON 文件导入导出选择器，MIT。
- path / path_provider：本地数据库路径，BSD-3-Clause。
- intl / collection：日期文本和集合工具，BSD-3-Clause。
- uuid：为本地用户数据生成同步友好的 UUID 主键，MIT。
- sqlite3：测试中创建旧版临时数据库以验证迁移，MIT。

## 第一版范围外

当前不做登录注册、真实云同步、多人共享、系统通知、AI 排程、系统日历双向同步、iPhone 打包发布、复杂项目管理和所有国家地区官方假期。
