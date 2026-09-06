"""usersテーブルのユーザー一覧を表示する確認ツール。"""

import sqlite3

from database import get_connection


def fetch_users() -> list[sqlite3.Row]:
    """登録順に、パスワードハッシュを除いたユーザー情報を取得する。"""
    with get_connection() as connection:
        return connection.execute(
            """
            SELECT id, email, status, plan, created_at
            FROM users
            ORDER BY id
            """
        ).fetchall()


def main() -> None:
    """全ユーザーを1行ずつ辞書形式で表示する。"""
    for user in fetch_users():
        print(dict(user))


if __name__ == "__main__":
    main()
