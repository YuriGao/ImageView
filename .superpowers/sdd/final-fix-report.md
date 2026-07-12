# ImageView 终审问题修复报告

日期：2026-07-12  
基线：`751274071aed799ebae56a5b2ef71af9eac2e17b`  
提交：`fix: close folder viewer integration review findings`（本报告随最终提交交付，精确 hash 见交付消息与 `git log -1`）

## 结论

终审列出的 1 个 Critical、3 个 Important、2 个 Minor 均已修复。所有文件操作测试只使用临时图片和注入的批量操作；未安装应用、未操作真实图片、未打开 GUI、未 push。

## RED 证据

首次 focused RED 命令：

```bash
swift test --disable-sandbox --filter 'FolderBrowserCellViewTests|FolderBrowserViewTests/testDoubleClickOnly|ViewerViewModelTests/test(RemovingEdited|RenameMigration)|MainWindowControllerTests/test(DirectViewer|GridTrash|GridMove|GridBackForward)'
```

失败证据：

- 动态颜色：`FolderBrowserCellView` 缺少有效外观变化刷新与颜色观测接口。
- 双击命中：`FolderBrowserView` 缺少按命中 item 打开的路径；原实现直接打开旧 selection。
- 当前项移除保护：`ViewerViewModel` 缺少移除后 pending edit 清理可验证行为。
- loading rename：旧实现仅迁移 URL 和 metadata，没有取消旧 display request 或从新 URL 重启。
- direct viewer 路由：`MainWindowController` 没有独立于 session membership 的显式 viewer 关联。
- scroll：没有对 `contentView.bounds.origin` 的往返断言接口。
- Trash/Move：测试覆盖 save/discard/cancel；原调用路径在确认批量参数后直接启动 operation，没有经过 viewer 未保存确认。Cancel 不启动 operation 是新增约束。

编译 RED 的代表性错误包括 `no member 'testingSelectionBackgroundColor'`、`no member 'pendingOperationCountForTesting'`、`no member 'folderBrowserScrollOriginForTesting'`、`no member 'testingPerformDoubleClick'`。随后逐项实现并运行 focused GREEN。

## GREEN 与修复内容

1. 批量 Trash/Move 未保存保护
   - 仅当 selection 包含 live viewer 当前 URL 时进入 save/discard/cancel。
   - Cancel 不启动注入的文件操作；save/discard 成功后才继续。
   - `removeItemsFromNavigation` 在当前项被移除时取消显示请求并清空 `pendingOperations/hasUnsavedEdits`，作为第二道保护。

2. direct viewer 与 Grid 的显式关联
   - 增加独立 `associatedViewerURL`，进入 Grid 前建立关联。
   - 关联不依赖扫描成功、非空或 item 是否出现在 session。
   - viewer 内 Previous/Next、批量 rename/remove 会同步迁移或清理关联。
   - 真实空扫描与真实失败扫描均可从 Grid 回到 live viewer。

3. loading/preview rename URL migration
   - 只有 full 且 live image/persisted image 均存在时才原位迁移 metadata。
   - loading/preview 时清除旧显示状态，由新的 generation 取消旧请求并从迁移后的 URL 重启 decode。

4. Aqua/Dark Aqua 动态颜色
   - cell 根视图监听 `viewDidChangeEffectiveAppearance`。
   - 在当前 effective appearance 下重新解析 selection background/border 动态色。

5. 双击 exactly-once
   - 双击 recognizer 只保留一个，要求 2 clicks。
   - action 使用 gesture location 命中 indexPath；命中 item 才打开，空白不再打开旧 selection。

6. Grid/Back/Forward scroll 保持
   - 自动化测试记录并比较 `NSScrollView.contentView.bounds.origin`，覆盖 viewer -> Back -> Forward -> Grid 往返。

focused 最终结果：10 tests，0 failures。

## 全套、Build、Scan

- 最终连续第 1 轮：334 tests，0 failures，6.815 秒。
- 最终连续第 2 轮：334 tests，0 failures，6.262 秒。
- `scripts/build-app.sh`：Release build 成功，产物 `.build/ImageView.app`。
- `/Users/zhupin/.codex/hooks/secret-scan.sh .`：退出码 0，输出 0 字节。
- `git diff --check`：通过。

## 自审

- route：显式关联在 direct viewer、grid item open、Previous/Next、rename、remove 生命周期内保持一致；显式打开新文件夹会清理旧关联。
- safety：Trash/Move Cancel 路径不会调用注入 operation；所有测试数据位于临时目录。
- async：loading/preview rename 通过 display generation 失效旧结果；full/live 路径不产生多余 decode。
- regression：现有 route/retry/hover/AX/localization 测试均包含在 334-test 全套内并通过。
- UI state：selection 动态颜色在 Aqua 与 Dark Aqua 运行时切换后重算；双击空白无副作用；scroll origin 不变。
- 范围：未 install、未 GUI、未 push，未修改真实图片。

未发现遗留阻塞或已知 concern。
