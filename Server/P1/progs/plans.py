"""P1が受け付ける利用プランと月間コンパイル上限を定義する。"""


PLAN_MONTHLY_LIMITS = {
    "free": 50,
    "standard": 1_000,
    "pro": 5_000,
}


def validated_plan(value: str) -> str:
    """正規化したプラン名を返し、未定義値は拒否する。"""
    plan = value.strip().lower()
    if plan not in PLAN_MONTHLY_LIMITS:
        allowed = ", ".join(PLAN_MONTHLY_LIMITS)
        raise ValueError(f"Plan must be one of: {allowed}")
    return plan
