# 启用 CI

`docs/ci-build.yml` 是现成的 GitHub Actions 工作流，但它**不能通过 API 直接放到
`.github/workflows/` 下** —— GitHub 禁止 API 对该目录的任何写入
（无论扩展名，缺 `workflow` scope 时一律返回 404，这是故意的安全限制）。

启用方式（用 git 命令行，不要用 API）：

```bash
# 1. 补上 workflow scope
gh auth refresh -h github.com -s workflow

# 2. 放到正确位置
mkdir -p .github/workflows
git mv docs/ci-build.yml .github/workflows/build.yml

# 3. 推送
git commit -m "ci: enable workflow"
git push
```

工作流做三件事：构建 library、构建 example、上传 APK 产物。
版本要求见 [01-getting-started.md](01-getting-started.md)。