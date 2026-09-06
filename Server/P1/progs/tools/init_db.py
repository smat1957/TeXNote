"""P1が使用するSQLiteデータベースとテーブルを初期化する。"""

import sqlite3

from database import DB_PATH


def create_database() -> None:
    """必要な3テーブルを、存在しない場合だけ作成する。"""
    connection = sqlite3.connect(DB_PATH)

    try:
        cursor = connection.cursor()
        cursor.execute("PRAGMA foreign_keys = ON")

        # ユーザー認証、状態、契約プランを保持する。
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                plan TEXT NOT NULL DEFAULT 'free',
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )

        # 将来の利用者別APIキー発行・失効管理に使用する。
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS api_keys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                key_hash TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                revoked_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
                    ON DELETE CASCADE
            )
            """
        )

        # コンパイル要求の所要時間、入力サイズ、成否を記録する。
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS usage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                compile_seconds REAL NOT NULL DEFAULT 0,
                input_bytes INTEGER NOT NULL DEFAULT 0,
                success INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (user_id) REFERENCES users(id)
                    ON DELETE CASCADE
            )
            """
        )

        connection.commit()
    finally:
        connection.close()


def main() -> None:
    """コマンドとしてDBを初期化し、作成先を表示する。"""
    create_database()
    print(f"Database initialized: {DB_PATH}")


if __name__ == "__main__":
    main()
