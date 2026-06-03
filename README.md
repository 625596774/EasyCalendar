# zrk_calendar

一个用 Flutter + Drift 打造的本地离线个人日历。它面向 Ubuntu Linux 桌面端，主视图是清爽的中文月历：每个日期同时显示公历和农历，内置常见中外节日、2026 年中国官方休/班安排，并支持按日期记录待办、管理公历/农历生日和纪念日。所有个人数据都保存在本机 SQLite 数据库中，不需要登录，不连接云端，也不依赖运行时网络接口。

适合想要一个“轻一点、私有一点、能看农历和调休”的个人桌面日历的人。当前版本是第一版可运行实现，重点放在本地持久化、月视图、待办、生日纪念日规则和 JSON 导入导出。

## 主要特性

- 月视图展示公历日期、农历日期、节日、休/班标记和待办摘要。
- 右侧详情面板展示当天农历、节日、生日/纪念日和待办列表。
- 待办支持添加、编辑、删除、完成/取消完成。
- 生日/纪念日支持公历或农历每年重复，预留农历闰月策略。
- 生日/纪念日规则支持 JSON 导入导出。
- 使用 Drift + SQLite 本地保存数据，应用关闭后仍保留。
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
└── shared/                      # 日期工具等共享代码
assets/data/holidays/            # 官方休班安排 JSON
test/                            # 单元测试
```

## 数据库表

`todo_items`

- `id`：自增主键
- `title`：标题
- `date`：绑定的公历日期
- `is_completed`：是否完成
- `note`：备注
- `created_at` / `updated_at`：创建和更新时间

`recurring_events`

- `id`：自增主键
- `title`：标题
- `event_type`：`birthday` 或 `anniversary`
- `calendar_type`：`solar` 或 `lunar`
- `month` / `day`：规则月日
- `is_leap_month`：是否农历闰月
- `leap_month_policy`：`useNormalMonth` 或 `skipThisYear`
- `note`：备注
- `enabled`：是否启用
- `created_at` / `updated_at`：创建和更新时间

## JSON 导入导出

第一版仅导入/导出生日和纪念日规则，不导入待办。

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

注意：该 JSON 只表示官方“休/班”安排，不表示节日本身。节日本身由 `FestivalService` 的本地规则判断。

## 第三方依赖

- Flutter / Dart：应用框架与语言，BSD-3-Clause。
- drift / drift_dev：SQLite ORM 与代码生成，MIT。
- sqlite3_flutter_libs：随应用提供 SQLite 动态库，MIT。
- lunar：农历转换，本地离线使用，MIT。
- file_picker：JSON 文件导入导出选择器，MIT。
- path / path_provider：本地数据库路径，BSD-3-Clause。
- intl / collection：日期文本和集合工具，BSD-3-Clause。

## 第一版范围外

当前不做登录注册、云同步、多人共享、系统通知、AI 排程、系统日历双向同步、iPhone 打包发布、复杂项目管理和所有国家地区官方假期。
