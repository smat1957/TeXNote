"""メールアドレスを指定して1ユーザーを確認するツール。"""

import argparse
import sqlite3

from database import get_connection


def find_user(email: str) -> sqlite3.Row | None:
    """パスワードハッシュを除いたユーザー情報をメールアドレスで検索する。"""
    with get_connection() as connection:
        return connection.execute(
            """
            SELECT id, email, status, plan, created_at
            FROM users
            WHERE email = ?
            """,
            (email,),
        ).fetchone()


def parse_arguments() -> argparse.Namespace:
    """コマンドライン引数を解析する。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("email", help="確認するユーザーのメールアドレス")
    return parser.parse_args()


def main() -> None:
    """指定ユーザーを表示し、存在しなければエラー終了する。"""
    arguments = parse_arguments()
    user = find_user(arguments.email)

    if user is None:
        raise SystemExit("User not found")

    print(dict(user))


if __name__ == "__main__":
    main()
