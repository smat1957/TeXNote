"""管理者が既存P1ユーザーの利用プランを変更するための保守ツール。"""

import argparse

from database import get_connection
from plans import PLAN_MONTHLY_LIMITS, validated_plan


def change_plan(email: str, requested_plan: str) -> tuple[str, str]:
    """ユーザーのプランを変更し、変更前と変更後の値を返す。"""
    normalized_email = email.strip()
    if not normalized_email:
        raise ValueError("Email is required")
    plan = validated_plan(requested_plan)

    with get_connection() as connection:
        user = connection.execute(
            "SELECT plan FROM users WHERE email = ?",
            (normalized_email,),
        ).fetchone()
        if user is None:
            raise LookupError("User not found")

        previous_plan = str(user["plan"])
        connection.execute(
            "UPDATE users SET plan = ? WHERE email = ?",
            (plan, normalized_email),
        )

    return previous_plan, plan


def parse_arguments() -> argparse.Namespace:
    """メールアドレスと変更先プランを解析する。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("email", help="変更するユーザーのメールアドレス")
    parser.add_argument(
        "plan",
        choices=tuple(PLAN_MONTHLY_LIMITS),
        help="変更後の利用プラン",
    )
    return parser.parse_args()


def main() -> None:
    """指定ユーザーのプランを変更し、結果を表示する。"""
    arguments = parse_arguments()
    try:
        previous_plan, plan = change_plan(arguments.email, arguments.plan)
    except (LookupError, ValueError) as error:
        raise SystemExit(str(error)) from error

    print(
        "Plan changed: "
        f"email={arguments.email.strip()}, "
        f"{previous_plan} -> {plan}"
    )


if __name__ == "__main__":
    main()
