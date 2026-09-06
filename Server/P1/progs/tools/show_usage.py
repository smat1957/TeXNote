"""コンパイル利用履歴と当月のユーザー別要求数を表示する。"""

from collections.abc import Iterable
import sqlite3

from database import get_connection


def fetch_usage_history() -> list[sqlite3.Row]:
    """新しい順に全コンパイル履歴を取得する。"""
    with get_connection() as connection:
        return connection.execute(
            """
            SELECT
                id,
                user_id,
                created_at,
                compile_seconds,
                input_bytes,
                success
            FROM usage
            ORDER BY id DESC
            """
        ).fetchall()


def fetch_monthly_counts() -> list[sqlite3.Row]:
    """当月に受け付けた要求数をユーザーごとに取得する。"""
    with get_connection() as connection:
        return connection.execute(
            """
            SELECT user_id, COUNT(*) AS count
            FROM usage
            WHERE strftime('%Y-%m', created_at) =
                  strftime('%Y-%m', 'now')
            GROUP BY user_id
            ORDER BY user_id
            """
        ).fetchall()


def print_rows(title: str, rows: Iterable[sqlite3.Row]) -> None:
    """見出しとSQLite行の一覧を辞書形式で表示する。"""
    print(f"{title}:")
    for row in rows:
        print(dict(row))


def main() -> None:
    """利用履歴と当月集計を続けて表示する。"""
    print_rows("Usage history", fetch_usage_history())
    print_rows("Monthly counts", fetch_monthly_counts())


if __name__ == "__main__":
    main()
