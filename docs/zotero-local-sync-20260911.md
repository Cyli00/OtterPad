# 桌面端利用本机 Zotero：源码调查与接入建议

调查日期：2026-09-11。核对官方 `main` 源码、`7.0.30` 标签和官方 Local API 文档。现已实现桌面本机导入首版；下文保留源码调查及后续方案。未读取用户实际 Zotero 数据库，尚未完成真实 Zotero 客户端联调。

## 已实现：现在如何使用

1. 打开 Zotero，在高级设置中允许这台电脑上的其他应用与它通信。
2. 在 OtterPad 的设置 → 数据管理 → Zotero 中打开“本机 Zotero”，点击“读取文库”。默认端口是 23119。
3. 旧版 Zotero 需要首次选择包含 `zotero.sqlite` 的资料库文件夹；程序只检查文件是否存在，用目录区分来源，不读取数据库。切换旧版资料库时必须重新选择对应目录。
4. 勾选文献，检查 PDF 选择，再点击“导入 / 更新所选文献”。一个 PDF 时默认选中，多个 PDF 时默认仅题录，由用户明确选择附件。

效果可以理解为：把 Zotero 的书目抄进 OtterPad，再把选中的 PDF 复印一份。重复操作不会重复添加同一来源条目。Zotero 改了题录，OtterPad 会更新仍保持上次导入值的字段；你在 OtterPad 手动改过的字段会保留。首次匹配到已有文献时，只补空字段。

第一版只支持个人库，手动触发单向导入。PDF 缺失时保留题录，下一次可补齐；已有 PDF 保留，不自动替换。取消时保留已完成文献并清理未完成副本。删除 OtterPad 文献不会删除 Zotero 原件。笔记、标注、群组库和后台自动同步尚未接入。

实现使用 `/api/users/0/items` 分页同时取得题录与附件关系，没有逐篇请求 children；新旧版本均不传 `since`。新版使用 `Zotero-Server-ID` 区分资料库并检测切库，旧版使用用户指定目录。来源关系和上次题录保存于现有 Drift `meta` 表，与云端同步记录分开，无数据库结构升级。PDF 复制走文献生命周期入口，先写临时文件、检查 PDF 文件头和计算内容指纹，再发布到 OtterPad 文献目录。

自动化验证涵盖本机接口分页、旧版未云同步条目、切库、中文路径、重复导入、题录保护、缺失和无效 PDF、取消清理、事务回滚，以及中英文 360dp 窗口的预览与实际导入。测试使用模拟接口与临时数据库，没有访问用户真实文库。新增测试位于 `test/`；本次提交按要求不纳入测试文件，测试保留在工作树中。

验证结果：相关回归 40 项通过，随后新增关闭窗口取消请求测试，并重跑受影响的 13 项，全部通过；合计覆盖 41 项。涉及的实现和测试文件 `dart analyze` 无问题。下一步实机验收建议选三篇：普通 PDF、一篇链接附件、一篇尚未下载 PDF；再次导入确认不重复，并修改一处 Zotero 题录确认更新。

## 人话结论

可以。Zotero 已经知道“这篇论文叫什么、作者是谁、PDF 放在哪里”，OtterPad 可以直接问正在运行的 Zotero，然后从本机取得 PDF，不必重新向云端下载。

建议先做“从 Zotero 导入或更新”，单向读取。第一版把选中的 PDF 复制到 OtterPad 自己的文献目录；以后即使 Zotero 没打开，也能照常阅读和备份。完全共用 Zotero 原文件同样可行，但需要单独解决改名、移盘、文件缺失和删除权限，不能只把现有路径改一下。

## Zotero 的文件实际怎么放

默认数据目录是用户主目录下的 `Zotero`，可以自定义。Windows 通常形如 `C:\Users\用户名\Zotero`，不应写死这个位置。[数据目录源码](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/dataDirectory.js)

```text
Zotero/                         ← 可由用户改到其他磁盘
├── zotero.sqlite               ← 题录、作者、附件关系、笔记、标注等
└── storage/
    ├── ABCD1234/               ← 附件自己的 key，不是论文的 key
    │   └── paper.pdf
    └── EFGH5678/
        └── supplement.pdf
```

上述是“由 Zotero 管理的附件”。数据库路径如 `storage:paper.pdf`，Zotero 用附件 key 找到对应子目录。另一种“链接附件”仍在用户原来的文件夹，可能保存绝对路径，也可能用 `attachments:` 表示相对于用户设置的附件基目录。因此，扫描 `storage/` 会漏掉链接附件。[附件存储与路径解析源码](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/attachments.js)

题录通过 `items`、`itemData`、`itemDataValues`、作者等表组合；附件用 `itemAttachments.parentItemID` 指回论文。笔记在 `itemNotes`，标注在 `itemAnnotations`，标注关联的是附件。只复制 PDF 不等于复制了 Zotero 笔记、标注；也不能假定一篇论文只有一个 PDF。[数据库结构](https://github.com/zotero/zotero/blob/main/resource/schema/userdata.sql)

## 最适合 OtterPad 的入口

使用官方 Local API，而不是直接打开 Zotero 的 SQLite 表。需要 Zotero 正在运行，并开启“设置 → 高级 → 允许此计算机上的其他应用程序与 Zotero 通信”。默认地址是 `http://localhost:23119/api/`，读取不需要云端 API Key。[官方说明](https://www.zotero.org/support/dev/web_api/v3/local_api)

建议的读取流程：

1. 请求 `/api/`，确认可连接及接口版本。
2. 从 `/api/users/0/items/top?format=json&limit=100&start=0` 分批取个人库题录。
3. 请求 `/api/users/0/items/{论文key}/children`，找 PDF 附件；多个附件要让用户选择，或明确采用主附件规则。
4. 请求 `/api/users/0/items/{附件key}/file/view/url`，取得 `file://` 地址。普通 `/file` 返回的是重定向，并非直接传输 PDF 字节。
5. 在 Dart 文件层解析本机路径，检查文件存在，再交给现有导入流程。阅读器仍使用 OtterPad 自己的 localhost 服务，不把 `file://` 直接交给 WebView。

上述文件接口在 `7.0.30` 中已存在；当前源码也保留这些入口。[7.0.30 接口源码](https://github.com/zotero/zotero/blob/7.0.30/chrome/content/zotero/xpcom/server/server_localAPI.js)、[当前接口源码](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/server/server_localAPI.js)

文件地址不保证实际文件已经在本机：未下载的云端附件、被移动的链接文件仍可能不可用。源码的异步路径查询明确检查文件存在。因此界面应区分“题录已同步”和“PDF 尚未在本机”，保留缺文件条目。[附件文件查询源码](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/data/item.js)

## 必须处理的版本差异

旧版 Local API 的 `since` 按云端同步版本筛选，可能漏掉尚未同步的本地新增或修改。`7.0.30` 源码使用 `dataObject.version`；当前实现改为 `clientVersion`。官方将本地版本号和 `Zotero-Server-ID` 的新语义列为 Zotero 10+。不能只看“API v3”就认定具备新版增量语义。[旧版筛选实现](https://github.com/zotero/zotero/blob/7.0.30/chrome/content/zotero/xpcom/server/server_localAPI.js)、[当前实现](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/server/server_localAPI.js)、[版本说明](https://www.zotero.org/support/dev/web_api/v3/local_api#object_versions)

因此建议：

- 旧版本或能力不确定时：分批读取题录，比较内容摘要，只更新有变化的条目；不要用 `since=0` 代替首次全量读取。
- 确认支持本地版本号时：再使用增量游标，并按 Zotero 实例和文库分别保存；本地游标与云端游标分开。
- PDF 是否变化单独检查，不能只靠题录版本；需要导入时计算内容指纹，避免重复复制。

## 项目内的实施顺序

以下是结合 OtterPad 现有架构提出的方案：

1. **先能连接并预览**：设置中增加桌面“本机 Zotero”来源，显示连接结果、题录数量和可用附件。云端来源继续保留。
2. **再导入选中的文献**：网络读取仍放在 `ZoteroSyncService`，字段转换仍由 `ZoteroItemMapper` 完成，PDF 复制和指纹去重交给现有导入模块。不要把 Zotero 字段散进普通文献模型。
3. **然后补更新关系**：当前同步簿记只有 `zoteroKey → documentId/version`，需要增加来源、实例、文库与附件 key 的区分，防止个人库、群组库和云端来源互相覆盖。更新先保留用户在 OtterPad 修改过的字段；删除不能直接双向传播。
4. **最后考虑完全共用 PDF**：显式区分“OtterPad 自有文件”和“Zotero 外部文件”。外部文件不得随 OtterPad 条目删除；备份必须说明是否包含 PDF；每次读取需能重新定位附件。这个阶段才涉及文件归属模型的调整。

首版验收：未同步的本地题录能看到；中文和空格路径能导入；链接附件可识别；重复同步不生成重复文献；缺失 PDF 有明确状态；取消不留半份文件；删除 OtterPad 条目不影响 Zotero 原件。
