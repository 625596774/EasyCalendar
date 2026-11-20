# zrk_calendar

一个用 Flutter + Drift 打造的个人日历。它面向 Ubuntu Linux、macOS 和 iOS，主视图是清爽的中文月历：每个日期同时显示公历和农历，内置常见中外节日、2026 年中国官方休/班安排，并支持按日期记录待办、管理公历/农历生日和纪念日。所有个人数据都会保存在本机 SQLite 数据库中；如果配置 Supabase，也可以使用邮箱密码登录后手动云同步。

适合想要一个“轻一点、私有一点、能看农历和调休”的个人桌面日历的人。当前版本是第一版可运行实现，重点放在本地持久化、月视图、待办、生日纪念日规则和 JSON 导入导出。

## 主要特性

- 月视图展示公历日期、农历日期、节日、休/班标记和待办摘要。
- 右侧详情面板展示当天农历、节日、生日/纪念日和待办列表。
- 待办支持添加、编辑（含日期）、删除、完成/取消完成。
- 支持 HTTPS ICS 日历订阅、课程时间与教室展示、离线缓存及个人备注。
- 课程、订阅活动和生日/纪念日可按具体日期勾选完成，完成后在月历中划线显示。
- 待办备注支持添加本机照片附件，并在待办列表中显示缩略图和大图预览。
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

当前 `schemaVersion = 3`。从 v1 升级到 v2 时，迁移会保留已有待办和生日/纪念日规则，为旧数据生成新的 UUID，并将旧数据标记为 `sync_status = pending`、`deleted_at = null`、`last_synced_at = null`。从 v2 升级到 v3 时，会为旧待办补充 `urgency = green`。

`todo_items`

- `id`：UUID 字符串主键
- `title`：标题
- `date`：绑定的公历日期
- `is_completed`：是否完成
- `urgency`：紧急程度，当前可为 `red`、`yellow`、`green`
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
- `urgency text not null default 'green'`
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

## 课程日历订阅

### 添加与使用

1. 桌面点击工具栏的“日历订阅”；手机点击“更多 → 日历订阅”。
2. 点击“添加订阅”，填写名称和学校提供的 HTTPS ICS 订阅地址，点击“读取预览”。
3. 核对预览后点击“保存订阅”。来源暂时没有日程时也可保存，后续仍会刷新。
4. 在月历中查看课程时间和标题，点击日期查看按香港时间排列的课程，再点开课程查看教室、原始说明及编辑个人备注。
5. 在订阅管理中可手动刷新、隐藏或移除来源，查看事件数量、最后成功更新时间和错误信息。移除订阅会同时移除该来源的本机缓存及个人备注。

当天详情中的课程和订阅活动可以像待办一样勾选完成；生日/纪念日可点击带勾选状态的标签完成。完成状态只属于当天这一次出现，例如今年完成某个生日不会自动完成明年的生日。勾选后，月历格子里的对应文字会变灰并划线，再次点击可恢复。

### 更新规则与限制

- 启动及回到前台时，距上次成功更新超过一小时会刷新；失败请求有五分钟退避，也可手动刷新。应用退出后不保证后台更新。
- 来源可分别隐藏、刷新和移除。通常按来源、UID 和 RECURRENCE-ID 区分事件。HKU 课表每次导出会重新生成 UUID，因此专门按课程标题和开始时间识别课次，并在同一天只有唯一对应课次时识别时间调整。跨日或有歧义的变化保留缓存待核对；不跨来源合并。
- 网络错误、无效日历和解析失败会保留缓存。源中消失的课次保留并标记待核对，明确标记 `STATUS:CANCELLED` 的事件才从显示缓存移除。
- 当前支持独立课次、全天/跨日事件、UTC、香港/上海时区和按香港时间解释的浮动时间。遇到 RRULE/RDATE/EXDATE 等重复规则或其他时区，会提示并保留缓存，尚不支持任意 ICS 源。
- 订阅配置、缓存及个人备注原子写入应用数据目录下的 `zrk_calendar/calendar_subscriptions.json`，与现有 SQLite 待办数据库独立，当前不参与 Supabase 云同步。其他设备可在订阅管理中分别添加同一链接。
- 活动完成状态保存在同一应用数据目录下的 `zrk_calendar/event_completions.json`，不会修改订阅源或生日/纪念日规则，当前也不参与 Supabase 云同步。

## 待办照片附件

添加或编辑待办时，可以在备注下方选择照片。每个待办最多添加 5 张，单张不超过 10 MB，支持 JPEG、PNG、WebP、GIF、HEIC 和 HEIF。应用会把所选照片复制到自己的 `zrk_calendar/todo_attachments/` 目录，删除附件时只删除这份应用副本，不会修改相册或原始文件。

附件清单保存在 `zrk_calendar/todo_attachments.json`，照片目前仅保存在本机，不参与 Supabase 同步；换设备或只同步待办时不会带上照片。待办列表会显示缩略图，点击可查看支持缩放的大图。

## 本地待办搜索

当天详情的“待办事项”标题旁提供搜索按钮。输入关键词后，会在所有日期的本地待办标题和备注，以及已导入日历的活动标题、来源名称、地点、说明和个人备注中进行不区分英文字母大小写的包含匹配。搜索也包含暂时隐藏但仍保存在本机的日历来源，不包含已取消的活动；结果按日期从新到旧显示，点击结果会跳转到对应日期。搜索只读取本机数据库和日历缓存，不会发起网络请求或修改数据。

月历工具栏和待办标题旁均提供“回到今天”操作。点击后会切换到当前月份、选中今天的日期格，并立即显示今天的待办；手机和小组件视图使用相同行为。

月历日期格会优先在上方展示未完成待办；已勾选、带删除线的待办排列在格子底部。格子空间不足时优先保留未完成项目，并用“还有 N 项”提示未显示内容。

- 订阅 URL 含私人访问凭证，不应提交到 Git；实际个人配置与验证数据放在已忽略的 `local_data/` 或应用数据目录。

### 隐私与开发验证

订阅地址中的 token 等参数可能允许读取个人日历。请在应用界面中输入个人链接，不要写入源码、README、测试用例或提交说明。仓库忽略原始 `.ics` / `.ical` 文件、`calendar_subscriptions.json`、`calendar_sources.json`、`local_data/` 和本地数据库；忽略规则不会自动移除已经被 Git 跟踪的文件，提交前仍需检查暂存内容。

仓库测试使用虚构日程，覆盖时区与日期解析、失败保留缓存、重复刷新、HKU 随机 UID、个人备注、同日改期，以及桌面和手机宽度下的布局。可运行：

```bash
flutter analyze
flutter test
```
