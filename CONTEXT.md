# OtterPad — Context

OtterPad 的领域语言。本文件只收录**本项目特有**的概念，不收通用编程术语。

## Language

### 后台任务与状态呈现

**Task Activity**:
应用中当前在跑的后台任务的**活集合**（提取、下载、翻译、同步、重构等），每个任务带进度、取消入口与终态结果。它是单一真值源——所有呈现处都观察它，而不是各自去抓 snackbar。
_Avoid_: task manager, task queue, notification center

**Active Task**:
Task Activity 中的一个成员：一次在跑的后台任务，由其生产者（如 `TaskRunner.runTask` / `DocumentTaskNotifier`）汇报，携带稳定 id、标题、进度、取消回调与终态结果。
_Avoid_: job（"job" 专指文档提取的远端 Job API），background work

**Task Surface**:
观察 Task Activity 并把它渲染出来的 adapter。当前有 snackbar surface（紧凑视图：1 个活跃显示完整进度，≥2 聚合为"N 个进行中"）；规划中的多文档任务面板是同一 seam 上的第二个 surface（完整列表视图）。
_Avoid_: view, widget, panel（"panel" 仅指那个具体的面板 surface）

**Transient Result**:
与 Task Activity 无关的一次性 snackbar 消息（复制成功、报错等，经 `SnackBarService.showResult`）。短暂占用单槽后让位，由 snackbar surface 重新呈现仍在跑的 Active Task。
_Avoid_: toast, flash message

## Flagged ambiguities

- **"task"** 一词此前同时指：全局 `TaskType`（库级，单槽）、`DocumentTaskType`（单篇，max 5 并发）、以及 UI 上的进度提示。统一为：二者都是 **Active Task** 的生产者，UI 上看到的是 **Task Surface** 对 **Task Activity** 的渲染。
- **"job"** 专指文档提取走的远端异步 Job API（`BatchExtractService`），不要用来泛指后台任务。

## Example dialogue

> **Dev:** 用户同时点了批量下载和一篇翻译，snackbar 该显示谁？
> **Domain:** 两个都是 Active Task，都进 Task Activity。snackbar surface 看到活集合 ≥2，就聚合成"2 个任务进行中"，不再互相顶掉。
> **Dev:** 那"复制成功"这种提示呢？
> **Domain:** 那是 Transient Result，不进 Task Activity。它短暂占槽，消失后 snackbar surface 把仍在跑的 Active Task 重新显示出来。
> **Dev:** 以后那个多文档面板呢？
> **Domain:** 它是第二个 Task Surface，观察同一个 Task Activity，只是渲染成完整列表。registry 不用改。
