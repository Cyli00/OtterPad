# Context

## 领域词汇

### 文献生命周期

文献生命周期描述一篇 `Document` 从进入 OtterPad 到被移除或恢复的完整过程：导入本地 PDF、通过标识符创建条目、补全文献元数据、绑定或重新下载 PDF、生成缩略图和抽取产物、加入或移出收藏夹、产生阅读历史、高亮和笔记、参与备份恢复，以及删除时级联清理所有关联状态与磁盘文件。

这个概念用于讨论文献库内围绕 `Document` 的一致性规则。调用方不应分别记忆“删文献还要删收藏夹引用、历史、高亮、缩略图、文献目录”等散落规则；这些规则属于文献生命周期的实现细节。

文献生命周期 Module 采用分层收口：`DocumentsNotifier` 保留为文献列表状态与持久化 Adapter，但页面、任务编排和阅读器动作不应直接调用它执行文献写操作。文献导入、标识符创建、绑定 PDF、重新下载 PDF、重建文库、删除文献、记录打开阅读器，以及某篇文献加入或移出收藏夹，都应通过文献生命周期入口表达意图，再由该 Module 协调 `documents`、`favorites`、`highlights`、`history`、缩略图与磁盘目录。

文献身份必须稳定，不能继续等同 PDF 内容 hash。多设备阅读同步需要同一篇文献在换 PDF、重新下载 PDF、跨设备合并高亮/笔记时保持同一个 `Document.id`；PDF 内容 hash 只能作为文件内容指纹或文献目录 key 的候选值，不能作为用户文献身份。旧数据迁移时需要把当前 hash 型 `Document.id` 视为 legacy stable id 的初始值，并逐步把收藏夹、高亮、历史等引用收敛到稳定 `documentId`。

文献目录收敛到稳定身份目录：新文献使用 `library/<documentId>/source.pdf`，`Document.id` 表示稳定文献身份，`Document.contentHash` 表示当前 PDF 内容指纹。路径应由 `DocPaths` 和文献生命周期 Module 统一派生，调用方不应自行从 hash 或文件名拼目录。

当前应用仍处于测试阶段，稳定身份重构不需要兼容既有缓存或旧文献库数据。可以要求用户清空数据后重新导入与识别，因此实现时不需要为旧 hash 型 `Document.id`、旧 `Favorite.docPaths`、旧 `Highlight.documentId=filePath` 或旧 `library/<hash>/` 目录写迁移逻辑；新模型可以成为唯一支持的写入与读取模型。

重新下载 PDF 后，旧 extract / figures / summary / 翻译缓存 / 缩略图与新 PDF 内容不一致的，由 redownloadPdf 按 contentHash 是否变化决定是否一并清理；restore 与 clearAllData 应对 documents / favorites / highlights / history 在内的内存状态做无差别 invalidate；service 层路径依赖统一指向 GStorage / DocPaths，不反向依赖 provider 层。

`Document.filePath` 不应长期保留。文献模型只保存稳定身份与领域元数据，文件系统路径统一由 `DocPaths` 按 `documentId` 派生。PDF 是否存在、抽取产物是否存在、翻译和摘要图路径等属于文献生命周期与 `DocPaths` 的实现细节；调用方不应持久化或传递任意绝对 PDF 路径作为文献身份。

无文件条目由 `Document.contentHash == null` 表示。绑定或重新下载 PDF 时，文献生命周期 Module 将 PDF 写入 `library/<documentId>/source.pdf` 并更新 `contentHash`；是否真的存在本地 PDF 文件由 `DocPaths` 派生路径与文件系统检查确定，不再通过空字符串 `filePath` 表示。
