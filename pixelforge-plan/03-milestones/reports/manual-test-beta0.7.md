# PixelForge Beta 0.7 项目所有者人工验收单

> 候选：`/Users/ruo/Desktop/PixelForge-0.7.0-beta.1-macOS.zip`
>
> SHA-256：`fd984990ecd44f7dd0c445d7b4b71f36b635a2eca70a81414e95c80fa5d71ba9`
>
> 当前状态：**工程通过、人工待验、发布未通过**
>
> 下列方框只由项目所有者填写；自动化、截图和构建者不能代填。

## 0. 准备

- [ ] 对桌面 ZIP 运行 `shasum -a 256`，确认与上方 SHA 完全一致。
- [ ] 解压到仓库外的新目录；不要覆盖旧候选。
- [ ] 只使用项目所有者有权使用的测试图片、临时项目目录和自己的 Provider key。
- [ ] 不把 key、用户图片、完整 prompt 或外部响应写进截图、报告或聊天。

## 1. 唯一主旅程

- [ ] 打开内置实例，确认卡片不拥挤，连线不穿卡，运行时 Output 通道位置清楚。
- [ ] OpenAI Image 与 RetroDiffusion 各执行一次最小 `batch=1` 真实生成。
- [ ] 观察 Queued、Running、不确定进度、连线流向和结果原位回填；没有伪百分比。
- [ ] 使用错误 key 检查 auth 弹窗；断网前提交一次以检查 network 错误和下一步动作。
- [ ] 启动后取消，确认先显示 Canceling、再 Canceled，且取消不弹终态错误框。
- [ ] 检查 Output 最多三行、内部滚动、单图拖出、拆出全部与 Undo。
- [ ] 连接 pixel_cleanup，修改一个参数后手动开始；确认顺序执行、产生新 Output、源 Output 不变。
- [ ] 确认 OpenAI 没有实际费用时显示“未知”而不是 `$0`；Retro 实际费用只累计一次。
- [ ] English 与简中各完成一次主旅程，检查卡片、Output、Provider 设置、错误框和 tooltip。
- [ ] 保存后重开，确认成功/Partial、拆出标记、清洗 provenance、历史 Output 均不丢失。
- [ ] 分别按 Space→左键释放和左键→Space 释放，确认画布不再粘滞平移。

无需用真实费用故意制造 rate limit、quota、content policy、partial、timeout 或重复计费；
这些分支已由本地 mock 自动化覆盖。

## 2. 环境与结果记录

```text
macOS 版本：
机器与显示器：
窗口/缩放：
English 结果：
简中结果：
OpenAI 最小请求结果：
RetroDiffusion 最小请求结果：
保存重开结果：
缺陷与复现步骤：
测试时间：
验收人：
```

## 3. 项目所有者签收

- [ ] `go`：上述人工项全部通过，可把 Beta 0.7 更新为“人工通过”；push、签名、公证和发布仍需另行授权。
- [ ] `修复后复验`：在当前未推送分支和已批准修复窗口内修复，重跑工程门并产生新候选后复验。
- [ ] `不通过`：保留现有证据与候选；任何破坏性回退等待项目所有者确认。
