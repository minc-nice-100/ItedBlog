#!/bin/bash

if [ ! -d ".git" ] || [ -f ".git/shallow" ]; then
  echo "执行完整克隆以获取提交历史..."
  rm -rf .git
  # 获取当前仓库的远程地址
  REMOTE_URL=$(git config --get remote.origin.url)
  if [ -z "$REMOTE_URL" ]; then
    # 如果没有远程地址，使用环境变量构建
    REMOTE_URL="https://github.com/${CF_PAGES_REPO_OWNER}/${CF_PAGES_REPO_NAME}.git"
  fi
  git clone $REMOTE_URL .
fi

# 正常构建
bundle exec jekyll build