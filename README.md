# zrk_calendar

一个用 Flutter + Drift 打造的个人日历。它面向 Ubuntu Linux、macOS 和 iOS，主视图是清爽的中文月历：每个日期同时显示公历和农历，内置常见中外节日、2026 年中国官方休/班安排，并支持按日期记录待办、管理公历/农历生日和纪念日。所有个人数据都会保存在本机 SQLite 数据库中；如果配置 Supabase，也可以使用邮箱密码登录后手动云同步。

适合想要一个“轻一点、私有一点、能看农历和调休”的个人桌面日历的人。当前版本是第一版可运行实现，重点放在本地持久化、月视图、待办、生日纪念日规则和 JSON 导入导出。

## 主要特性

- 月视图展示公历日期、农历日期、节日、休/班标记和待办摘要。
- 右侧详情面板展示当天农历、节日、生日/纪念日和待办列表。
- 待办支持添加、编辑、删除、完成/取消完成。
- 生日/纪念日支持公历或农历每年重复，预留农历闰月策略。
- 生日/纪念日规则支持 JSON 导入导出。
- 使用 Drift + SQLite 本地保存数据，应用关闭后仍保留。
- 用户数据使用 UUID、软删除和同步字段，支持 Supabase 云同步第一版。
- 官方假期和节日规则均为本地数据或本地规则。

## 运行

Linux：

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

macOS：

```bash
flutter config --enable-macos-desktop
flutter doctor -v
flutter pub get
flutter run -d macos
```

macOS 需要安装完整 Xcode，而不只是 Command Line Tools。安装后通常还需要执行：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

如果 `flutter doctor -v` 提示 CocoaPods 缺失，需要先安装 CocoaPods，否则带平台代码的插件可能无法在 macOS/iOS 工程中正确集成。

iOS：

```bash
flutter doctor -v
flutter pub get
flutter devices
```

模拟器调试运行：

```bash
flutter run -d <ios-simulator-device-id> --dart-define-from-file=.env
```

真机调试运行：

```bash
flutter run -d <iphone-device-id> --dart-define-from-file=.env
```

如果只使用本地模式，可以省略 `--dart-define-from-file=.env`。如果需要 Supabase 登录和同步，推荐使用 `.env` 中的 `SUPABASE_URL` 和 `SUPABASE_PUBLISHABLE_KEY` 通过 `--dart-define-from-file=.env` 注入；不要把 `.env` 提交到 Git。

真机运行前需要在 Xcode 中确认签名配置：

1. 打开 `ios/Runner.xcworkspace`。
2. 选择 `Runner` target。
3. 在 `Signing & Capabilities` 中选择自己的 Apple Developer Team。
4. 确认 Bundle Identifier 不与已有 App 冲突。

当前 iPhone 端已做窄屏适配：顶部工具栏压缩为图标操作，主视图固定为月历，点击日期后使用底部弹层查看当日详情。左右滑动可以切换月份。App 内“小组件模式”入口仅保留在桌面宽屏布局中。

如需安装一个可以从 iPhone 桌面直接打开的调试/发布模式构建，可以使用：

```bash
flutter run --release -d <iphone-device-id> --dart-define-from-file=.env
```

真机 release/profile 构建仍依赖本机 Xcode 签名和设备信任配置；当前项目没有配置 App Store 发布、WidgetKit target 或 App Groups。

## 验证

```bash
flutter analyze
flutter test
flutter build linux
flutter build macos
flutter build ios --no-codesign
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
│   └── sync/                    # Supabase 同步、同步模型与 Noop 本地模式
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

## Supabase 云同步

当前版本已接入 Supabase 云同步第一版：

- 支持邮箱密码登录和退出登录。
- 支持点击顶部“同步”入口后手动同步。
- App 启动后如果已有 Supabase session，会自动同步一次。
- 同步范围包括 `todo_items` 和 `recurring_events`。
- 本地未配置 Supabase 或未登录时，日历、待办、生日/纪念日仍可离线使用。
- 当前不支持实时同步、OAuth、多人共享或服务端函数。
- 冲突策略为 `updated_at` 后写 wins，不创建冲突副本。

`.env` 配置示例见 `.env.example`：

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
```

`SUPABASE_URL` 不要包含 `/rest/v1/`。当前桌面版会先从运行目录读取 `.env`，如果没找到，会从应用可执行文件所在目录向上查找父目录；开发时通常放在项目根目录即可，Linux 和 macOS 都使用同样规则。发布后如果需要云同步，也可以把同样格式的 `.env` 放在可执行文件旁边。

macOS 版本启用了 App Sandbox，并在 entitlements 中允许出站网络访问和用户选择文件读写。出站网络用于 Supabase 登录和同步，用户选择文件读写用于 JSON 导入导出。

Supabase 云端表需要开启 RLS，并确保用户只能读写自己的数据。云端表结构：

`todo_items`

- `id uuid primary key`
- `user_id uuid not null references auth.users(id)`
- `title text not null`
- `date date not null`
- `is_completed boolean not null`
- `note text`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`
- `deleted_at timestamptz`

`recurring_events`

- `id uuid primary key`
- `user_id uuid not null references auth.users(id)`
- `title text not null`
- `event_type text not null`
- `calendar_type text not null`
- `month int not null`
- `day int not null`
- `is_leap_month boolean not null`
- `leap_month_policy text not null`
- `note text`
- `enabled boolean not null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`
- `deleted_at timestamptz`

安全注意：

- `.env`、本地 SQLite 数据库、个人导入导出的 JSON 文件不应提交到 Git。
- Supabase 的 `service_role` key、database password、secret key 绝不能写入 Flutter 客户端或 GitHub。
- Flutter 客户端只能使用 Supabase URL 和 publishable/anon key。
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
- supabase_flutter：Supabase Auth 和 PostgREST 云同步客户端，MIT。
- flutter_dotenv：读取本地 `.env` 中的 Supabase URL 和 publishable key，MIT。
- path / path_provider：本地数据库路径，BSD-3-Clause。
- intl / collection：日期文本和集合工具，BSD-3-Clause。
- uuid：为本地用户数据生成同步友好的 UUID 主键，MIT。

## 第一版范围外

当前不做实时同步、OAuth 第三方登录、多人共享、系统通知、AI 排程、系统日历双向同步、App Store 发布、WidgetKit、App Groups、复杂项目管理和所有国家地区官方假期。
