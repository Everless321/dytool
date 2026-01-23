"""
用户解析路由
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import asyncio

router = APIRouter()


class UserParseRequest(BaseModel):
    url: str
    cookie: Optional[str] = None


class UserProfile(BaseModel):
    sec_user_id: str
    uid: Optional[str] = None
    nickname: Optional[str] = None
    signature: Optional[str] = None
    avatar: Optional[str] = None
    following_count: Optional[int] = None
    follower_count: Optional[int] = None
    aweme_count: Optional[int] = None
    favoriting_count: Optional[int] = None
    total_favorited: Optional[int] = None


class UserParseResponse(BaseModel):
    success: bool
    message: str
    data: Optional[UserProfile] = None


@router.post("/parse", response_model=UserParseResponse)
async def parse_user(request: UserParseRequest):
    """
    解析抖音用户链接，获取用户信息

    支持的链接格式:
    - https://v.douyin.com/xxxxx
    - https://www.douyin.com/user/xxxxx
    """
    from f2.apps.douyin.utils import SecUserIdFetcher
    from f2.apps.douyin.handler import DouyinHandler

    try:
        # 1. 从 URL 提取 sec_user_id
        sec_user_id = await SecUserIdFetcher.get_sec_user_id(request.url)

        if not sec_user_id:
            return UserParseResponse(
                success=False,
                message="无法从链接提取用户ID，请确认链接格式正确",
                data=None
            )

        # 2. 检查 cookie
        cookie = request.cookie or ""
        if not cookie or len(cookie) < 100:
            return UserParseResponse(
                success=False,
                message="需要配置有效的 Cookie 才能获取用户信息，请在设置中配置抖音 Cookie",
                data=UserProfile(sec_user_id=sec_user_id)  # 返回已解析的 sec_user_id
            )

        # 3. 配置 handler
        kwargs = {
            "headers": {
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Referer": "https://www.douyin.com/",
            },
            "proxies": {"http://": None, "https://": None},
            "cookie": cookie,
        }

        # 4. 获取用户信息
        handler = DouyinHandler(kwargs)
        user = await handler.fetch_user_profile(sec_user_id=sec_user_id)

        if not user:
            return UserParseResponse(
                success=False,
                message="获取用户信息失败，请检查 Cookie 是否有效",
                data=UserProfile(sec_user_id=sec_user_id)
            )

        # 5. 提取用户数据
        raw_data = user._to_dict() if hasattr(user, '_to_dict') else {}

        # 处理头像 URL
        avatar = None
        avatar_larger = raw_data.get("avatar_larger")
        if isinstance(avatar_larger, dict):
            url_list = avatar_larger.get("url_list", [])
            if url_list:
                avatar = url_list[0]
        elif isinstance(avatar_larger, str):
            avatar = avatar_larger

        profile = UserProfile(
            sec_user_id=sec_user_id,
            uid=raw_data.get("uid"),
            nickname=raw_data.get("nickname"),
            signature=raw_data.get("signature"),
            avatar=avatar,
            following_count=raw_data.get("following_count"),
            follower_count=raw_data.get("follower_count"),
            aweme_count=raw_data.get("aweme_count"),
            favoriting_count=raw_data.get("favoriting_count"),
            total_favorited=raw_data.get("total_favorited"),
        )

        return UserParseResponse(
            success=True,
            message="解析成功",
            data=profile
        )

    except Exception as e:
        error_msg = str(e)
        if "sec_user_id" in error_msg:
            return UserParseResponse(
                success=False,
                message="无法解析用户链接，请使用完整的用户主页链接 (https://www.douyin.com/user/xxx)",
                data=None
            )
        if "重试次数达到上限" in error_msg or "响应内容为空" in error_msg:
            return UserParseResponse(
                success=False,
                message="Cookie 无效或已过期，请重新配置",
                data=None
            )
        return UserParseResponse(
            success=False,
            message=f"解析失败: {error_msg}",
            data=None
        )


@router.get("/extract-id")
async def extract_sec_user_id(url: str):
    """
    仅提取 sec_user_id，不获取详细信息
    """
    from f2.apps.douyin.utils import SecUserIdFetcher

    try:
        sec_user_id = await SecUserIdFetcher.get_sec_user_id(url)

        if sec_user_id:
            return {"success": True, "sec_user_id": sec_user_id}
        else:
            return {"success": False, "error": "无法提取用户ID"}
    except Exception as e:
        return {"success": False, "error": str(e)}
