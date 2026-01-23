# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

dyTool is a macOS native application for batch downloading Douyin (TikTok China) videos. Built with SwiftUI, it wraps the [f2](https://github.com/JoeanAmier/f2) command-line tool and provides a GUI for managing users and downloads.

## Build & Run

```bash
# Build the macOS app
xcodebuild -project dyTool.xcodeproj -scheme dyTool -configuration Debug build

# Run the backend (optional, for user profile parsing)
cd backend && source venv/bin/activate && uvicorn app.main:app --reload
```

Open `dyTool.xcodeproj` in Xcode for development. The app requires macOS 26.1+ and Apple Silicon.

## Architecture

### Swift Client (dyTool/)

**Service Layer** (singleton pattern via `.shared`):
- `F2Service` - Wraps f2-cli binary, handles download execution (serial/parallel), process management
- `DatabaseService` - SQLite storage for users and settings, publishes `@Published` state
- `DownloadState` - Shared download progress state
- `AnalysisService` - Video content analysis features
- `BackendService` - HTTP client for Python backend API (curl fallback for ATS bypass)

**Data Flow**: Services are `@StateObject` singletons injected via `.environmentObject()` from `dyToolApp.swift`. Views subscribe to published properties.

**Views**: NavigationSplitView layout with 4 sections (users, download, videos, analysis). Each view consumes services via `@EnvironmentObject`.

**f2-cli Integration**: Binary bundled in `Resources/f2-cli`. `F2Service` spawns processes with arguments like `f2-cli dy -M post -u <url> -k <cookie> -p <path>`. Supports parallel downloads via semaphore-controlled dispatch.

### Python Backend (backend/)

FastAPI service for parsing Douyin user profiles. Runs on `localhost:8000`.

```
backend/
├── app/
│   ├── main.py        # FastAPI app, CORS, router mounting
│   └── routers/
│       └── users.py   # /api/users/parse endpoint
└── requirements.txt   # fastapi, uvicorn, f2, httpx
```

Swift client calls backend via `BackendService.parseUser()` to fetch user metadata (nickname, aweme_count, etc.) before downloads.

## Key Patterns

- **Download Modes**: post, like, collection, collects, mix, music (mirrors f2 modes)
- **Cookie Auth**: User must provide Douyin web cookie for API access
- **App Sandbox**: Uses `~/Library/Application Support/dyTool/` for DB and downloads
- **Menu Bar**: App persists in menu bar after window close (`applicationShouldTerminateAfterLastWindowClosed` returns false)

## Database Schema

```sql
-- users table
id TEXT PRIMARY KEY, url TEXT UNIQUE, mode TEXT, max_counts INTEGER,
interval TEXT, nickname TEXT, path TEXT, aweme_count INTEGER

-- settings table (key-value store)
key TEXT PRIMARY KEY, value TEXT
```
