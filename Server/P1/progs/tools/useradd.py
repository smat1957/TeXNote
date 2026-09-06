"""管理者が対話操作でP1ユーザーを追加するための保守ツール。"""

from getpass import getpass
from sqlite3 import IntegrityError

from auth import create_user
from plans import validated_plan


DEFAULT_PLAN = "free"


def prompt_user_data() -> tuple[str, str, str]:
    """メールアドレス、プラン、確認済みパスワードを対話入力する。"""
    email = input("Email: ").strip()
    plan = input(f"Plan [{DEFAULT_PLAN}]: ").strip() or DEFAULT_PLAN
    password = getpass("Password: ")
    password_again = getpass("Password (again): ")

    if not email:
        raise SystemExit("Email is required")
    if not password:
        raise SystemExit("Password is required")
    if password != password_again:
        raise SystemExit("Passwords do not match")

    try:
        plan = validated_plan(plan)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    return email, password, plan


def main() -> None:
    """入力内容でユーザーを登録し、発行されたIDを表示する。"""
    email, password, plan = prompt_user_data()

    try:
        user_id = create_user(email, password, plan)
    except IntegrityError as error:
        # users.emailのUNIQUE制約違反を管理者向けの表示へ変換する。
        raise SystemExit("Email is already registered") from error

    print(f"User created: id={user_id}, email={email}, plan={plan}")


if __name__ == "__main__":
    main()
