"""TeXNote P1のユーザー登録とパスワード認証を提供する。"""

import sqlite3

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from database import get_connection
from plans import validated_plan


# Argon2の安全な既定パラメーターでハッシュ生成・照合を行う。
password_hasher = PasswordHasher()


def create_user(email: str, password: str, plan: str = "free") -> int:
    """パスワードをArgon2でハッシュ化し、新しいユーザーを登録する。"""
    plan = validated_plan(plan)
    password_hash = password_hasher.hash(password)

    with get_connection() as connection:
        cursor = connection.execute(
            """
            INSERT INTO users (
                email,
                password_hash,
                plan
            )
            VALUES (?, ?, ?)
            """,
            (email, password_hash, plan),
        )
        user_id = cursor.lastrowid

    # AUTOINCREMENTで発行されたIDは通常intだが、型上はNoneの可能性がある。
    if user_id is None:
        raise sqlite3.DatabaseError("Failed to obtain the new user ID")

    return int(user_id)


def authenticate_user(email: str, password: str) -> sqlite3.Row | None:
    """有効なユーザーのパスワードが一致すれば、そのDB行を返す。"""
    with get_connection() as connection:
        user = connection.execute(
            """
            SELECT *
            FROM users
            WHERE email = ?
            """,
            (email,),
        ).fetchone()

    # ユーザー不存在とパスワード不一致は呼び出し側で同じ認証失敗として扱う。
    if user is None:
        return None

    # 発行済みJWTがあっても、停止ユーザーは新たにログインさせない。
    if user["status"] != "active":
        return None

    try:
        password_hasher.verify(user["password_hash"], password)
    except VerifyMismatchError:
        return None

    return user
