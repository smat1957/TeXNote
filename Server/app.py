import asyncio
import base64
import binascii
import os
import resource
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Literal
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field


MAX_REQUEST_BYTES = 25 * 1024 * 1024
MAX_SOURCE_CHARACTERS = 2_000_000
MAX_ASSET_BYTES = 10 * 1024 * 1024
MAX_TOTAL_ASSET_BYTES = 20 * 1024 * 1024
MAX_ASSETS_PER_FOLDER = 50
MAX_LOG_CHARACTERS = 200_000
PROCESS_TIMEOUT_SECONDS = 35

ENGINES: dict[str, tuple[str, bool]] = {
    "lualatex": ("/usr/bin/lualatex", False),
    "xelatex": ("/usr/bin/xelatex", False),
    "pdflatex": ("/usr/bin/pdflatex", False),
    "uplatex": ("/usr/bin/uplatex", True),
    "platex": ("/usr/bin/platex", True),
}

compile_slots = asyncio.Semaphore(2)
app = FastAPI(title="TeXNote Typesetting Server", version="1.0.0")


class CardAsset(BaseModel):
    model_config = ConfigDict(extra="forbid")

    fileName: str = Field(min_length=1, max_length=255)
    data: str = Field(min_length=1)


class TypesettingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cardID: UUID
    engine: Literal["lualatex", "xelatex", "pdflatex", "uplatex", "platex"]
    source: str = Field(min_length=1, max_length=MAX_SOURCE_CHARACTERS)
    pictures: list[CardAsset] = Field(max_length=MAX_ASSETS_PER_FOLDER)
    files: list[CardAsset] = Field(max_length=MAX_ASSETS_PER_FOLDER)


class TypesettingResponse(BaseModel):
    pdfBase64: str
    log: str


class HealthResponse(BaseModel):
    status: str
    engines: list[str]


@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > MAX_REQUEST_BYTES:
                return JSONResponse(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    content={"message": "リクエストが大きすぎます。"},
                )
        except ValueError:
            return JSONResponse(
                status_code=status.HTTP_400_BAD_REQUEST,
                content={"message": "Content-Lengthが不正です。"},
            )
    return await call_next(request)


def require_api_token(authorization: str | None = Header(default=None)) -> None:
    expected = os.environ.get("TEXNOTE_API_TOKEN")
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="サーバーのAPIトークンが設定されていません。",
        )
    if authorization != f"Bearer {expected}":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="認証に失敗しました。",
            headers={"WWW-Authenticate": "Bearer"},
        )


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    available = [
        engine
        for engine, (executable, _) in ENGINES.items()
        if os.access(executable, os.X_OK)
    ]
    return HealthResponse(status="ok", engines=available)


@app.get(
    "/v1/auth-check",
    dependencies=[Depends(require_api_token)],
)
async def auth_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post(
    "/v1/typeset",
    response_model=TypesettingResponse,
    dependencies=[Depends(require_api_token)],
)
async def typeset(payload: TypesettingRequest) -> TypesettingResponse:
    executable, produces_dvi = ENGINES[payload.engine]
    if not os.access(executable, os.X_OK):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"TeXエンジンが見つかりません: {payload.engine}",
        )

    decoded_pictures, decoded_files = decode_assets(
        payload.pictures,
        payload.files,
    )

    async with compile_slots:
        return await asyncio.to_thread(
            compile_document,
            executable,
            produces_dvi,
            payload.source,
            decoded_pictures,
            decoded_files,
        )


def decode_assets(
    pictures: list[CardAsset],
    files: list[CardAsset],
) -> tuple[list[tuple[str, bytes]], list[tuple[str, bytes]]]:
    total_bytes = 0

    def decode_folder(assets: list[CardAsset]) -> list[tuple[str, bytes]]:
        nonlocal total_bytes
        decoded: list[tuple[str, bytes]] = []
        seen_names: set[str] = set()

        for asset in assets:
            validate_file_name(asset.fileName)
            if asset.fileName in seen_names:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"ファイル名が重複しています: {asset.fileName}",
                )
            seen_names.add(asset.fileName)

            try:
                content = base64.b64decode(asset.data, validate=True)
            except (binascii.Error, ValueError) as error:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Base64データが不正です: {asset.fileName}",
                ) from error

            if len(content) > MAX_ASSET_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail=f"ファイルが大きすぎます: {asset.fileName}",
                )
            total_bytes += len(content)
            if total_bytes > MAX_TOTAL_ASSET_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail="添付ファイルの合計サイズが大きすぎます。",
                )
            decoded.append((asset.fileName, content))
        return decoded

    return decode_folder(pictures), decode_folder(files)


def validate_file_name(file_name: str) -> None:
    if (
        file_name in {".", ".."}
        or file_name.startswith(".")
        or "/" in file_name
        or "\\" in file_name
        or "\x00" in file_name
        or Path(file_name).name != file_name
    ):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"利用できないファイル名です: {file_name}",
        )


def compile_document(
    executable: str,
    produces_dvi: bool,
    source: str,
    pictures: list[tuple[str, bytes]],
    files: list[tuple[str, bytes]],
) -> TypesettingResponse:
    with tempfile.TemporaryDirectory(prefix="texnote-") as temporary_path:
        work_directory = Path(temporary_path)
        write_inputs(work_directory, source, pictures, files)
        environment = restricted_environment(work_directory)
        log_parts: list[str] = []

        if produces_dvi:
            for file_name, _ in pictures:
                if Path(file_name).suffix.lower() in {".jpg", ".jpeg", ".png", ".pdf"}:
                    log_parts.append(
                        run_process(
                            ["/usr/bin/extractbb", "-x", f"pics/{file_name}"],
                            work_directory,
                            environment,
                        )
                    )

        tex_arguments = [
            executable,
            "-no-shell-escape",
            "-interaction=nonstopmode",
            "-file-line-error",
            "-halt-on-error",
            "main.tex",
        ]
        for _ in range(2):
            log_parts.append(
                run_process(tex_arguments, work_directory, environment)
            )

        if produces_dvi:
            log_parts.append(
                run_process(
                    ["/usr/bin/dvipdfmx", "main.dvi"],
                    work_directory,
                    environment,
                )
            )

        pdf_path = work_directory / "main.pdf"
        if not pdf_path.is_file():
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="PDFを生成できませんでした。",
            )

        log = "".join(log_parts)
        return TypesettingResponse(
            pdfBase64=base64.b64encode(pdf_path.read_bytes()).decode("ascii"),
            log=log[-MAX_LOG_CHARACTERS:],
        )


def write_inputs(
    work_directory: Path,
    source: str,
    pictures: list[tuple[str, bytes]],
    files: list[tuple[str, bytes]],
) -> None:
    (work_directory / "pics").mkdir(mode=0o700)
    (work_directory / "files").mkdir(mode=0o700)
    (work_directory / "tex-cache").mkdir(mode=0o700)
    (work_directory / "main.tex").write_text(source, encoding="utf-8")

    for folder_name, assets in (("pics", pictures), ("files", files)):
        for file_name, content in assets:
            (work_directory / folder_name / file_name).write_bytes(content)


def restricted_environment(work_directory: Path) -> dict[str, str]:
    return {
        "HOME": str(work_directory),
        "PATH": "/usr/bin:/bin",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "openin_any": "p",
        "openout_any": "p",
        "TEXMFCACHE": str(work_directory / "tex-cache"),
        "TEXMFVAR": str(work_directory / "tex-cache"),
        "TEXMFOUTPUT": str(work_directory),
    }


def apply_resource_limits() -> None:
    resource.setrlimit(resource.RLIMIT_CPU, (30, 35))
    resource.setrlimit(resource.RLIMIT_AS, (1_500_000_000, 1_500_000_000))
    resource.setrlimit(resource.RLIMIT_FSIZE, (50_000_000, 50_000_000))
    resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))


def run_process(
    arguments: list[str],
    work_directory: Path,
    environment: dict[str, str],
) -> str:
    try:
        result = subprocess.run(
            arguments,
            cwd=work_directory,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=PROCESS_TIMEOUT_SECONDS,
            check=False,
            preexec_fn=apply_resource_limits,
        )
    except subprocess.TimeoutExpired as error:
        raise HTTPException(
            status_code=status.HTTP_408_REQUEST_TIMEOUT,
            detail="版組処理がタイムアウトしました。",
        ) from error

    output = result.stdout[-MAX_LOG_CHARACTERS:]
    if result.returncode != 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=output or f"版組処理に失敗しました（終了値 {result.returncode}）。",
        )
    return output


@app.exception_handler(HTTPException)
async def http_exception_handler(_request: Request, error: HTTPException):
    return JSONResponse(
        status_code=error.status_code,
        content={"message": str(error.detail)},
        headers=error.headers,
    )
