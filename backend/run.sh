#!/bin/bash
# dyTool Backend 启动脚本

cd "$(dirname "$0")"

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "创建虚拟环境..."
    python3 -m venv venv
fi

# 激活虚拟环境
source venv/bin/activate

# 安装依赖
echo "检查依赖..."
pip install -r requirements.txt -q

# 启动服务
echo "启动服务 http://localhost:8000"
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
