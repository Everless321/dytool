"""
dyTool Backend - 抖音解析服务
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import users

app = FastAPI(
    title="dyTool Backend",
    description="抖音视频解析服务",
    version="0.1.0"
)

# CORS 配置 - 允许本地 Swift 客户端访问
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"status": "ok", "service": "dyTool Backend"}


@app.get("/health")
async def health():
    return {"status": "healthy"}


# 用户解析路由
app.include_router(users.router, prefix="/api/users", tags=["users"])
