"""TeXNote P1 認証・API中継サーバー。

外部ユーザーの認証と利用制限を担当し、認証済みのコンパイル要求だけを
内部ネットワーク上のP2 TeXサーバーへ転送する。
"""

import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Literal

import jwt
import requests
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordBearer
from jwt.exceptions import InvalidTokenError
from pydantic import BaseModel, Field

from auth import authenticate_user
from database import get_connection
from plans import PLAN_MONTHLY_LIMITS


# ---------------------------------------------------------------------------
# アプリケーション設定
# ---------------------------------------------------------------------------

app = FastAPI(
    title="TeXNote Authentication API",
    version="1.0.0",
)

# 秘密値はソースコードへ書かず、起動環境から受け取る。
SECRET_KEY = os.environ["TEX_AUTH_SECRET_KEY"]
P2_API_TOKEN = os.environ["TEXNOTE_API_TOKEN"]

JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
MAX_REQUEST_BYTES = 32 * 1024 * 1024

# P2の移設に備えて環境変数で上書きできるようにし、現行値を既定値とする。
P2_TYPESET_URL = os.getenv(
    "TEXNOTE_P2_TYPESET_URL",
    "http://192.168.3.4:8000/v1/typeset",
)
P2_REQUEST_TIMEOUT_SECONDS = 30

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")
SERVICE_NAME = "texnote"


# ---------------------------------------------------------------------------
# HTTPリクエスト制限
# ---------------------------------------------------------------------------

@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    """Content-Lengthが32 MiBを超える要求を処理前に拒否する。"""
    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            request_bytes = int(content_length)
        except ValueError:
            return JSONResponse(
                status_code=status.HTTP_400_BAD_REQUEST,
                content={"detail": "Content-Lengthが不正です。"},
            )

        if request_bytes > MAX_REQUEST_BYTES:
            return JSONResponse(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                content={
                    "detail": "リクエストの上限32 MiBを超えています。"
                },
            )

    return await call_next(request)


# ---------------------------------------------------------------------------
# API入出力モデル
# ---------------------------------------------------------------------------

class LoginRequest(BaseModel):
    email: str
    password: str
    service: Literal["texnote"]


class FileData(BaseModel):
    relativePath: str
    data: str


class CompileRequest(BaseModel):
    engine: Literal[
        "lualatex",
        "xelatex",
        "pdflatex",
        "uplatex",
        "platex",
    ] = "lualatex"
    source: str
    pictures: list[FileData] = Field(default_factory=list)
    files: list[FileData] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# JWTとユーザー認証
# ---------------------------------------------------------------------------

def create_access_token(user_id: int, email: str) -> str:
    """ユーザーIDとメールアドレスを含む短寿命JWTを発行する。"""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "email": email,
        "aud": SERVICE_NAME,
        "iat": now,
        "exp": now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=JWT_ALGORITHM)


def unauthorized(detail: str) -> HTTPException:
    """Bearer認証用ヘッダーを含む401例外を生成する。"""
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user(token: str = Depends(oauth2_scheme)):
    """JWTを検証し、現在も有効なユーザーをDBから取得する。"""
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[JWT_ALGORITHM],
            audience=SERVICE_NAME,
        )
        user_id = int(payload["sub"])
    except (InvalidTokenError, KeyError, TypeError, ValueError):
        raise unauthorized("Invalid or expired token")

    with get_connection() as con:
        user = con.execute(
            "SELECT * FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()

    if user is None:
        raise unauthorized("User not found")

    if user["status"] != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User is inactive",
        )

    return user


# ---------------------------------------------------------------------------
# 利用履歴と月間制限
# ---------------------------------------------------------------------------

def get_monthly_usage_count(user_id: int) -> int:
    """当月に受け付けたコンパイル要求数（成功・失敗の両方）を返す。"""
    with get_connection() as con:
        row = con.execute(
            """
            SELECT COUNT(*) AS count
            FROM usage
            WHERE user_id = ?
              AND strftime('%Y-%m', created_at) =
                  strftime('%Y-%m', 'now')
            """,
            (user_id,),
        ).fetchone()

    return int(row["count"])


def record_usage(
    user_id: int,
    compile_seconds: float,
    input_bytes: int,
    success: bool,
) -> None:
    """コンパイル要求の所要時間、入力サイズ、成否を記録する。"""
    with get_connection() as con:
        con.execute(
            """
            INSERT INTO usage (
                user_id,
                compile_seconds,
                input_bytes,
                success
            )
            VALUES (?, ?, ?, ?)
            """,
            (
                user_id,
                compile_seconds,
                input_bytes,
                1 if success else 0,
            ),
        )


def ensure_monthly_limit(user) -> None:
    """プランの月間上限を超えていればHTTP 429で拒否する。"""
    plan = user["plan"]
    monthly_limit = PLAN_MONTHLY_LIMITS.get(
        plan,
        PLAN_MONTHLY_LIMITS["free"],
    )
    monthly_count = get_monthly_usage_count(user["id"])

    if monthly_count >= monthly_limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "message": "Monthly compile limit exceeded",
                "plan": plan,
                "limit": monthly_limit,
                "used": monthly_count,
            },
        )


# ---------------------------------------------------------------------------
# P2コンパイルサーバーとの通信
# ---------------------------------------------------------------------------

def send_typeset_request(payload: dict) -> dict:
    """内部トークン付きでP2へ要求し、JSON応答を返す。"""
    try:
        response = requests.post(
            P2_TYPESET_URL,
            headers={"Authorization": f"Bearer {P2_API_TOKEN}"},
            json=payload,
            timeout=P2_REQUEST_TIMEOUT_SECONDS,
        )
    except requests.RequestException as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"P2 connection failed: {error}",
        ) from error

    if response.status_code != status.HTTP_200_OK:
        # P2の独自エラー形式 {"message": "..."} とFastAPI標準形式
        # {"detail": "..."} の両方から本文だけを取り出す。
        p2_detail = response.text
        try:
            p2_error = response.json()
            if isinstance(p2_error, dict):
                detail = p2_error.get("message") or p2_error.get("detail")
                if isinstance(detail, str) and detail:
                    p2_detail = detail
        except ValueError:
            pass

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={
                "message": "P2 compile failed",
                "p2_status": response.status_code,
                "p2_detail": p2_detail,
            },
        )

    try:
        result = response.json()
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="P2 returned an invalid JSON response",
        ) from error

    if not isinstance(result, dict):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="P2 returned an unexpected response",
        )

    return result


def make_typeset_payload(request: CompileRequest) -> dict:
    """P1の入力モデルをP2 /v1/typeset用のJSONへ変換する。"""
    return {
        "cardID": str(uuid.uuid4()),
        "engine": request.engine,
        "source": request.source,
        "pictures": [item.model_dump() for item in request.pictures],
        "files": [item.model_dump() for item in request.files],
    }


# ---------------------------------------------------------------------------
# 公開API
# ---------------------------------------------------------------------------

@app.post("/login")
def login(request: LoginRequest):
    """メールアドレスとパスワードを検証してJWTを返す。"""
    user = authenticate_user(request.email, request.password)
    if user is None:
        raise unauthorized("Invalid email or password")

    return {
        "access_token": create_access_token(user["id"], user["email"]),
        "token_type": "bearer",
    }


@app.get("/me")
def me(user=Depends(get_current_user)):
    """JWTに対応する現在のユーザー情報を返す。"""
    plan = user["plan"]
    return {
        "service": SERVICE_NAME,
        "id": user["id"],
        "email": user["email"],
        "plan": plan,
        "status": user["status"],
        "used": get_monthly_usage_count(user["id"]),
        "limit": PLAN_MONTHLY_LIMITS.get(
            plan,
            PLAN_MONTHLY_LIMITS["free"],
        ),
    }


@app.post("/compile-test")
def compile_test(user=Depends(get_current_user)):
    """固定の最小文書でP1からP2までの経路を確認する。"""
    payload = {
        "cardID": str(uuid.uuid4()),
        "engine": "lualatex",
        "source": r"""
\documentclass{article}
\begin{document}
Hello from P1.
\end{document}
""",
        "pictures": [],
        "files": [],
    }
    result = send_typeset_request(payload)

    return {
        "message": "compile succeeded",
        "user_id": user["id"],
        "pdf_received": bool(result.get("pdfBase64")),
        "log": result.get("log", ""),
    }


@app.post("/compile")
def compile_tex(
    request: CompileRequest,
    user=Depends(get_current_user),
):
    """利用上限を確認し、ユーザーのTeX文書をP2でコンパイルする。"""
    ensure_monthly_limit(user)

    start_time = time.monotonic()
    input_bytes = len(request.source.encode("utf-8"))
    success = False

    try:
        result = send_typeset_request(make_typeset_payload(request))
        success = True
        return {
            "user_id": user["id"],
            "pdfBase64": result.get("pdfBase64"),
            "log": result.get("log", ""),
        }
    finally:
        # P2接続失敗やコンパイル失敗も1回の要求として記録する。
        record_usage(
            user_id=user["id"],
            compile_seconds=time.monotonic() - start_time,
            input_bytes=input_bytes,
            success=success,
        )
