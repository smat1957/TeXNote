"""TeXNoteの登録済み利用者へ新しいパスワードを設定する管理ツール。"""

from getpass import getpass
import sys

from argon2 import PasswordHasher

from database import get_connection


def main() -> None:
    """対象利用者を確認し、新しいArgon2ハッシュだけをDBへ保存する。"""
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python -m tools.reset_password EMAIL")

    email = sys.argv[1].strip()
    if not email:
        raise SystemExit("Email is required")

    new_password = getpass("New password: ")
    confirmation = getpass("New password (again): ")
    if not new_password:
        raise SystemExit("Password is required")
    if new_password != confirmation:
        raise SystemExit("Passwords do not match")

    # 平文はDBへ保存せず、Argon2で新たに作ったハッシュへ置き換える。
    password_hash = PasswordHasher().hash(new_password)
    with get_connection() as connection:
        cursor = connection.execute(
            "UPDATE users SET password_hash = ? WHERE email = ?",
            (password_hash, email),
        )

    if cursor.rowcount != 1:
        raise SystemExit(f"User not found: {email}")

    print(f"Password updated: {email}")


if __name__ == "__main__":
    main()
