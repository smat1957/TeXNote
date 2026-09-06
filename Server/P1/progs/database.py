"""TeXNote P1で使用するSQLite接続を提供する。

DBファイルの位置と接続時の共通設定をこのモジュールへ集約し、
運転用コードと保守ツールが必ず同じデータベースを参照するようにする。
"""

from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
import sqlite3


# このファイルと同じディレクトリにP1のDBを配置する。
DB_PATH = Path(__file__).resolve().parent / "tex_service.db"


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    """共通設定済みのDB接続を開き、処理後に必ず閉じる。"""
    connection = sqlite3.connect(DB_PATH)

    # SELECT結果を row["email"] のように列名で参照できるようにする。
    connection.row_factory = sqlite3.Row

    # SQLiteの外部キー制約は接続ごとに有効化する必要がある。
    connection.execute("PRAGMA foreign_keys = ON")

    try:
        # withブロックが正常終了した場合はコミットし、例外時はロールバックする。
        with connection:
            yield connection
    finally:
        connection.close()
