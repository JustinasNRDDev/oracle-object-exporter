from __future__ import annotations

import argparse
import datetime as dt
import logging
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

if os.name == "nt":
    import winreg


VALID_STEPS = {
    "packages",
    "procedures",
    "functions",
    "types",
    "table_ddl",
    "view_ddl",
}

ROUTINE_STEPS = {"packages", "procedures", "functions", "types"}
DDL_STEPS = {"table_ddl", "view_ddl"}
VALID_DDL_SOURCES = {"all", "dba"}
STEP_PRIORITY = ["packages", "procedures", "functions", "types", "table_ddl", "view_ddl"]

DEFAULT_EXPORT_EXTENSIONS = {
    "packages": "pck",
    "procedures": "prc",
    "functions": "fnc",
    "types": "typ",
    "table_ddl": "sql",
    "view_ddl": "sql",
}

STEP_ALIASES = {
    "packages": "packages",
    "package": "packages",
    "procedures": "procedures",
    "procedure": "procedures",
    "functions": "functions",
    "function": "functions",
    "types": "types",
    "type": "types",
    "tables": "table_ddl",
    "table": "table_ddl",
    "table_ddl": "table_ddl",
    "views": "view_ddl",
    "view": "view_ddl",
    "view_ddl": "view_ddl",
}

SQL_ERROR_PATTERN = re.compile(r"\b(ORA-\d+|SP2-\d+)\b", re.IGNORECASE)
POST_EXPORT_ERROR_PATTERN = re.compile(
    r"\b(ORA-\d+|SP2-\d+|PLS-\d+|TNS-\d+)\b",
    re.IGNORECASE,
)


def normalize_extension(value: str) -> str:
    """Normalize extension values from config to a ".ext" form."""
    ext = value.strip().lower().lstrip(".")
    if not ext:
        return ""
    return f".{ext}"


class ExporterError(RuntimeError):
    """Domain-specific exporter exception."""


@dataclass
class RunSummary:
    total_steps: int = 0
    executed_steps: int = 0
    skipped_steps: int = 0
    failed_steps: int = 0
    post_check_scanned_files: int = 0
    post_check_findings: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Oracle object exporter. Supports classic YAML mode and task mode: "
            "oracle_exporter.exe <TASK> <ENV> [SCHEMA]"
        )
    )
    parser.add_argument(
        "task_name",
        nargs="?",
        help="Task folder/path containing objects.txt (task mode).",
    )
    parser.add_argument(
        "task_env",
        nargs="?",
        help="Environment section in objects.txt (task mode), e.g. DEV.",
    )
    parser.add_argument(
        "task_schema",
        nargs="?",
        help="Optional schema filter in task mode.",
    )
    parser.add_argument(
        "--config",
        default="config/exporter.yaml",
        help="Path to YAML config file.",
    )
    parser.add_argument(
        "--env",
        action="append",
        dest="envs",
        help="Environment name from config (can be repeated). Default: all environments.",
    )
    parser.add_argument(
        "--schema",
        action="append",
        dest="schemas",
        help="Schema name filter (can be repeated). Default: all schemas in environment.",
    )
    parser.add_argument(
        "--timestamp",
        help="Custom timestamp (default format: YYYYMMDDTHHMMSS).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without executing sqlplus.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Force strict SQL error detection regardless of config value.",
    )
    parser.add_argument(
        "--no-strict",
        action="store_true",
        help="Disable strict SQL error detection regardless of config value.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug-level console logs.",
    )
    parser.add_argument(
        "--skip-post-check",
        action="store_true",
        help="Skip automatic post-export scan for ORA/SP2/PLS/TNS errors in generated artifacts.",
    )
    parser.add_argument(
        "--post-check-max-findings",
        type=int,
        default=200,
        help="Maximum number of post-check findings to collect before stopping the scan.",
    )
    parser.add_argument(
        "--nls-lang",
        help="Override NLS_LANG for this run.",
    )
    parser.add_argument(
        "--task-root",
        help="Base directory for task folders (default: defaults.task_root or 'tasks').",
    )
    parser.add_argument(
        "--task-objects-file",
        help="Objects file name inside task folder (default: defaults.task_objects_file_name or 'objects.txt').",
    )
    return parser.parse_args()


def normalize_list(values: list[str] | None) -> list[str]:
    if not values:
        return []

    normalized: list[str] = []
    seen: set[str] = set()

    for raw in values:
        for token in raw.split(","):
            value = token.strip()
            if not value:
                continue
            key = value.upper()
            if key not in seen:
                seen.add(key)
                normalized.append(key)

    return normalized


def normalize_step_alias(step_name: str) -> str:
    normalized = STEP_ALIASES.get(step_name.strip().lower(), "")
    if not normalized:
        raise ExporterError(f"Unsupported object/step key in config: '{step_name}'.")
    return normalized


def parse_object_names(raw_value: Any) -> list[str]:
    if raw_value is None:
        return []

    values: list[str] = []
    if isinstance(raw_value, str):
        values = [part.strip() for part in raw_value.split(",")]
    elif isinstance(raw_value, list):
        for item in raw_value:
            if isinstance(item, str):
                values.extend(part.strip() for part in item.split(","))
            else:
                values.append(str(item).strip())
    else:
        values = [str(raw_value).strip()]

    deduped: list[str] = []
    seen: set[str] = set()
    for value in values:
        if not value:
            continue
        if value not in seen:
            seen.add(value)
            deduped.append(value)
    return deduped


def parse_export_extensions(raw_value: Any, source_name: str) -> dict[str, str]:
    if raw_value is None:
        return {}

    if not isinstance(raw_value, dict):
        raise ExporterError(f"{source_name}.export_extensions must be a mapping.")

    parsed: dict[str, str] = {}
    for key, value in raw_value.items():
        step = normalize_step_alias(str(key))
        extension = str(value).strip().lstrip(".").lower()
        if not extension:
            raise ExporterError(
                f"{source_name}.export_extensions.{key} must not be empty."
            )
        if not re.fullmatch(r"[a-z0-9_]+", extension):
            raise ExporterError(
                f"{source_name}.export_extensions.{key} has invalid extension '{value}'."
            )
        parsed[step] = extension
    return parsed


def parse_environment_export_objects(
    env_name: str,
    env_config: dict[str, Any],
) -> dict[str, dict[str, list[str]]]:
    raw_export_objects = env_config.get("export_objects")
    if raw_export_objects is None:
        return {}

    if not isinstance(raw_export_objects, dict):
        raise ExporterError(
            f"Environment {env_name}: export_objects must be a mapping of schema to objects."
        )

    parsed: dict[str, dict[str, list[str]]] = {}

    for raw_schema_name, raw_schema_cfg in raw_export_objects.items():
        schema_name = str(raw_schema_name).strip().upper()
        if not schema_name:
            continue

        if not isinstance(raw_schema_cfg, dict):
            raise ExporterError(
                f"Environment {env_name}, schema {schema_name}: value must be a mapping."
            )

        objects_cfg = raw_schema_cfg.get("objects", raw_schema_cfg)
        if not isinstance(objects_cfg, dict):
            raise ExporterError(
                f"Environment {env_name}, schema {schema_name}: objects must be a mapping."
            )

        step_to_objects: dict[str, list[str]] = {}
        for raw_key, raw_value in objects_cfg.items():
            step = normalize_step_alias(str(raw_key))
            names = parse_object_names(raw_value)
            if names:
                step_to_objects[step] = names

        if step_to_objects:
            parsed[schema_name] = step_to_objects

    return parsed


def merge_unique_names(target: list[str], incoming: list[str]) -> None:
    seen = set(target)
    for name in incoming:
        if name not in seen:
            target.append(name)
            seen.add(name)


def resolve_task_objects_file(
    *,
    project_root: Path,
    defaults: dict[str, Any],
    task_name: str,
    task_root_override: str | None,
    task_objects_file_override: str | None,
) -> tuple[Path, str]:
    task_root = str(task_root_override or defaults.get("task_root", "tasks")).strip()
    objects_file_name = str(
        task_objects_file_override or defaults.get("task_objects_file_name", "objects.txt")
    ).strip()

    if not objects_file_name:
        raise ExporterError("Task objects file name must not be empty.")

    raw = Path(expand_env_vars(task_name))
    candidates: list[Path] = []

    if raw.is_absolute():
        candidates.append(raw)
    else:
        candidates.append(project_root / raw)
        if task_root:
            candidates.append(project_root / task_root / raw)

    tried_paths: list[Path] = []

    for candidate in candidates:
        resolved = candidate.resolve()
        tried_paths.append(resolved)

        if resolved.is_file():
            return resolved, resolved.parent.name

        if resolved.is_dir():
            objects_path = (resolved / objects_file_name).resolve()
            tried_paths.append(objects_path)
            if objects_path.exists() and objects_path.is_file():
                return objects_path, resolved.name

    tried = "\n - ".join(str(path) for path in tried_paths)
    raise ExporterError(
        "Task objects file not found. Checked:\n - " + tried
    )


def parse_task_objects_file(objects_file: Path) -> dict[str, dict[str, Any]]:
    try:
        lines = objects_file.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError as exc:
        raise ExporterError(f"Could not read task objects file: {objects_file} ({exc})") from exc

    environments: dict[str, dict[str, Any]] = {}
    current_env = ""
    current_schema = ""

    for line_no, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#") or line.startswith("--") or line.startswith(";"):
            continue

        if line.startswith("[") and line.endswith("]"):
            env_name = line[1:-1].strip().upper()
            if not env_name:
                raise ExporterError(
                    f"Task objects file {objects_file}, line {line_no}: empty environment section."
                )
            current_env = env_name
            current_schema = ""
            environments.setdefault(
                env_name,
                {
                    "nls_lang": "",
                    "export_objects": {},
                },
            )
            continue

        if not current_env:
            raise ExporterError(
                f"Task objects file {objects_file}, line {line_no}: line outside [ENV] section."
            )

        if ":" not in line:
            raise ExporterError(
                f"Task objects file {objects_file}, line {line_no}: expected key:value format."
            )

        key_raw, value_raw = line.split(":", 1)
        key = key_raw.strip().lower()
        value = value_raw.strip()

        env_entry = environments[current_env]

        if key == "nls_lang":
            env_entry["nls_lang"] = value
            continue

        if key == "schema":
            schema_name = value.strip().upper()
            if not schema_name:
                raise ExporterError(
                    f"Task objects file {objects_file}, line {line_no}: schema name is empty."
                )
            current_schema = schema_name
            env_entry["export_objects"].setdefault(schema_name, {})
            continue

        if not current_schema:
            raise ExporterError(
                f"Task objects file {objects_file}, line {line_no}: define schema before object lists."
            )

        step = normalize_step_alias(key)
        names = parse_object_names(value)
        if not names:
            continue

        schema_objects = env_entry["export_objects"].setdefault(current_schema, {})
        existing = schema_objects.setdefault(step, [])
        merge_unique_names(existing, names)

    parsed: dict[str, dict[str, Any]] = {}
    for env_name, env_entry in environments.items():
        export_objects = env_entry.get("export_objects", {})
        if not export_objects:
            continue
        parsed[env_name] = {
            "nls_lang": str(env_entry.get("nls_lang", "")).strip(),
            "export_objects": export_objects,
        }

    return parsed


def current_timestamp() -> str:
    return dt.datetime.now().strftime("%Y%m%dT%H%M%S")


def configure_logger(log_file: Path, verbose: bool) -> logging.Logger:
    logger = logging.getLogger("universal_exporter")
    logger.setLevel(logging.DEBUG)
    logger.handlers.clear()

    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")

    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setLevel(logging.DEBUG if verbose else logging.INFO)
    stream_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)

    return logger


def load_config(config_path: Path) -> dict[str, Any]:
    if not config_path.exists():
        raise ExporterError(f"Config file not found: {config_path}")

    try:
        config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise ExporterError(f"Invalid YAML config: {exc}") from exc

    if not isinstance(config, dict):
        raise ExporterError("Config root must be a YAML object.")

    required_root_keys = ["defaults", "environments"]
    missing = [key for key in required_root_keys if key not in config]
    if missing:
        raise ExporterError(
            "Missing required config key(s): " + ", ".join(sorted(missing))
        )

    return config


def expand_env_vars(value: str) -> str:
    expanded = os.path.expandvars(value)

    if os.name != "nt":
        return expanded

    pattern = re.compile(r"%([A-Za-z_][A-Za-z0-9_]*)%")

    def replace_from_windows_registry(match: re.Match[str]) -> str:
        var_name = match.group(1)

        process_value = os.getenv(var_name, "")
        if process_value:
            return process_value

        for hive, subkey in (
            (winreg.HKEY_CURRENT_USER, r"Environment"),
            (
                winreg.HKEY_LOCAL_MACHINE,
                r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment",
            ),
        ):
            try:
                with winreg.OpenKey(hive, subkey) as key:
                    registry_value, _ = winreg.QueryValueEx(key, var_name)
                if registry_value:
                    return str(registry_value)
            except OSError:
                continue

        return match.group(0)

    return pattern.sub(replace_from_windows_registry, expanded)


def resolve_path(base_dir: Path, path_value: str) -> Path:
    path = Path(expand_env_vars(path_value))
    if not path.is_absolute():
        path = base_dir / path
    return path.resolve()


def resolve_connection_string(
    project_root: Path,
    env_name: str,
    env_config: dict[str, Any],
) -> str:
    direct_connection = str(env_config.get("connection", "")).strip()
    if direct_connection:
        return direct_connection

    env_var_name = str(env_config.get("connection_env_var", "")).strip()
    if env_var_name:
        connection_from_env = os.getenv(env_var_name, "").strip()
        if connection_from_env:
            return connection_from_env
        raise ExporterError(
            f"Environment {env_name}: connection_env_var '{env_var_name}' is empty."
        )

    connection_file_cfg = str(env_config.get("connection_file", "")).strip()
    if connection_file_cfg:
        connection_file = resolve_path(project_root, connection_file_cfg)
        if not connection_file.exists():
            raise ExporterError(
                f"Environment {env_name}: connection_file not found: {connection_file}"
            )

        content = connection_file.read_text(encoding="utf-8", errors="ignore").strip()
        if not content:
            raise ExporterError(
                f"Environment {env_name}: connection_file is empty: {connection_file}"
            )

        first_line = content.splitlines()[0].strip()
        if not first_line:
            raise ExporterError(
                f"Environment {env_name}: first line in connection_file is empty: {connection_file}"
            )
        return first_line

    raise ExporterError(
        f"Environment {env_name}: define one of connection, connection_env_var, connection_file."
    )


def read_object_list(list_file: Path) -> list[str]:
    if not list_file.exists():
        return []

    result: list[str] = []
    seen: set[str] = set()

    for line in list_file.read_text(encoding="utf-8", errors="ignore").splitlines():
        item = line.strip()
        if not item:
            continue
        if item.startswith("#") or item.startswith("--"):
            continue
        if item not in seen:
            seen.add(item)
            result.append(item)

    return result


def sql_escape_single_quotes(value: str) -> str:
    return value.replace("'", "''")


def build_sqlplus_command(
    sqlplus_executable: str,
    connection: str,
    script_file: Path,
    args: list[str],
) -> list[str]:
    return [sqlplus_executable, connection, f"@{script_file}", *args]


def has_sqlplus_errors(output: str) -> bool:
    return bool(SQL_ERROR_PATTERN.search(output))


def run_sqlplus(
    *,
    sqlplus_executable: str,
    connection: str,
    script_file: Path,
    args: list[str],
    cwd: Path,
    env: dict[str, str],
    strict_mode: bool,
    dry_run: bool,
    logger: logging.Logger,
) -> None:
    cmd = build_sqlplus_command(sqlplus_executable, connection, script_file, args)
    masked_display_cmd = [sqlplus_executable, "<connection-redacted>", f"@{script_file}", *args]
    display = " ".join(masked_display_cmd)

    if dry_run:
        logger.info("DRY-RUN | %s", display)
        return

    logger.info("EXECUTE | %s", display)
    process = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )

    output = (process.stdout or "") + (process.stderr or "")
    if process.stdout:
        logger.info(process.stdout.rstrip())
    if process.stderr:
        logger.error(process.stderr.rstrip())

    if process.returncode != 0:
        raise ExporterError(
            f"sqlplus exited with code {process.returncode} for script: {script_file}"
        )

    if strict_mode and has_sqlplus_errors(output):
        raise ExporterError(
            f"Detected ORA-/SP2- errors in sqlplus output for script: {script_file}"
        )


def write_routine_list_script(
    *,
    step: str,
    schema: str,
    objects: list[str],
    generated_dir: Path,
    file_extension: str,
) -> Path:
    generated_dir.mkdir(parents=True, exist_ok=True)

    script_name = f"list_{step}_{schema}.sql"
    script_path = generated_dir / script_name

    lines: list[str] = ["define save_directory=&1", ""]

    for obj in objects:
        if step == "packages":
            lines.append(
                f"@scripts/validate_and_export_package &save_directory {obj} SPEC_AND_BODY {schema} {file_extension}"
            )
        elif step == "procedures":
            lines.append(
                f"@scripts/validate_and_export_procedure &save_directory {obj} {schema} {file_extension}"
            )
        elif step == "functions":
            lines.append(
                f"@scripts/validate_and_export_function &save_directory {obj} {schema} {file_extension}"
            )
        elif step == "types":
            lines.append(
                f"@scripts/validate_and_export_type &save_directory {obj} {schema} {file_extension}"
            )
        else:
            raise ExporterError(f"Unsupported routine step: {step}")

    lines.extend(["", "exit", ""])
    script_path.write_text("\n".join(lines), encoding="utf-8")
    return script_path


def write_ddl_master_script(
    *,
    step: str,
    schema: str,
    objects: list[str],
    save_dir: Path,
    scripts_dir: Path,
    generated_dir: Path,
    timestamp: str,
    ddl_source: str,
    file_extension: str,
) -> Path:
    generated_dir.mkdir(parents=True, exist_ok=True)

    header_path = scripts_dir / "master_header.sql"
    footer_path = scripts_dir / "master_footer.sql"

    if not header_path.exists() or not footer_path.exists():
        raise ExporterError(
            "DDL generation requires scripts/master_header.sql and scripts/master_footer.sql."
        )

    header = header_path.read_text(encoding="utf-8", errors="ignore").rstrip("\n")
    footer = footer_path.read_text(encoding="utf-8", errors="ignore").rstrip("\n")

    if ddl_source not in VALID_DDL_SOURCES:
        raise ExporterError(f"Unsupported ddl_source '{ddl_source}'.")

    if step == "table_ddl":
        check_name_col = "table_name"
        if ddl_source == "dba":
            check_source = "dba_tables"
            generator_script = "generate_tbl_ddl_dba"
        else:
            check_source = "all_tables"
            generator_script = "generate_tbl_ddl"
    elif step == "view_ddl":
        check_name_col = "view_name"
        if ddl_source == "dba":
            check_source = "dba_views"
            generator_script = "generate_view_ddl_dba"
        else:
            check_source = "all_views"
            generator_script = "generate_view_ddl"
    else:
        raise ExporterError(f"Unsupported DDL step: {step}")

    script_path = generated_dir / f"master_{step}_{schema}.sql"

    lines: list[str] = [f"REM script generated at {timestamp}", header, "column tbl_exists new_val table_exists"]

    escaped_schema = sql_escape_single_quotes(schema)
    save_dir_str = str(save_dir)

    for obj in objects:
        escaped_obj = sql_escape_single_quotes(obj)
        lines.extend(
            [
                "SET TERM OFF",
                (
                    "select DECODE(count(*), 0, '- NOT EXISTS', ' - EXISTS') tbl_exists "
                    f"from {check_source} "
                    f"WHERE owner = UPPER('{escaped_schema}') "
                    f"AND {check_name_col} = UPPER('{escaped_obj}');"
                ),
                "SET TERM ON",
                f"prompt {obj} &table_exists",
                f"@scripts/{generator_script} {save_dir_str} {schema} {obj} {file_extension}",
            ]
        )

    lines.extend(["", footer, ""])
    script_path.write_text("\n".join(lines), encoding="utf-8")
    return script_path


def resolve_output_dir(
    *,
    output_root: Path,
    env_name: str,
    timestamp: str,
    schema: str,
    step: str,
    output_cfg: dict[str, Any],
) -> Path:
    schema_root = output_root / env_name / timestamp / schema

    if step == "types":
        subdir = str(output_cfg.get("types_subdirectory", "TYPES")).strip()
        return schema_root / subdir if subdir else schema_root

    if step == "table_ddl":
        subdir = str(output_cfg.get("tables_subdirectory", "TABLES")).strip()
        return schema_root / subdir if subdir else schema_root

    if step == "view_ddl":
        subdir = str(output_cfg.get("views_subdirectory", "VIEWS")).strip()
        return schema_root / subdir if subdir else schema_root

    subdir = str(output_cfg.get("routines_subdirectory", "")).strip()
    return schema_root / subdir if subdir else schema_root


def execute_step(
    *,
    env_name: str,
    schema: str,
    step: str,
    catalog: dict[str, Any],
    objects_override: list[str] | None,
    output_root: Path,
    output_cfg: dict[str, Any],
    scripts_dir: Path,
    generated_sql_dir: Path,
    connection: str,
    sqlplus_executable: str,
    subprocess_env: dict[str, str],
    strict_mode: bool,
    dry_run: bool,
    timestamp: str,
    project_root: Path,
    ddl_source: str,
    file_extension: str,
    logger: logging.Logger,
    summary: RunSummary,
) -> None:
    summary.total_steps += 1

    list_path_for_log = "<yaml:export_objects>"

    if objects_override is None:
        schema_cfg = catalog.get(schema, {})
        if not isinstance(schema_cfg, dict):
            logger.warning("SKIP | %s.%s | Invalid schema catalog definition", schema, step)
            summary.skipped_steps += 1
            return

        list_path_raw = str(schema_cfg.get(step, "")).strip()
        if not list_path_raw:
            logger.warning("SKIP | %s.%s | No object list configured", schema, step)
            summary.skipped_steps += 1
            return

        list_path = resolve_path(project_root, list_path_raw)
        list_path_for_log = str(list_path)
        objects = read_object_list(list_path)
    else:
        objects = parse_object_names(objects_override)

    if not objects:
        logger.warning(
            "SKIP | %s.%s | Object list is empty or missing (%s)",
            schema,
            step,
            list_path_for_log,
        )
        summary.skipped_steps += 1
        return

    save_dir = resolve_output_dir(
        output_root=output_root,
        env_name=env_name,
        timestamp=timestamp,
        schema=schema,
        step=step,
        output_cfg=output_cfg,
    )
    save_dir.mkdir(parents=True, exist_ok=True)

    if step in ROUTINE_STEPS:
        script_file = write_routine_list_script(
            step=step,
            schema=schema,
            objects=objects,
            generated_dir=generated_sql_dir,
            file_extension=file_extension,
        )
    elif step in DDL_STEPS:
        script_file = write_ddl_master_script(
            step=step,
            schema=schema,
            objects=objects,
            save_dir=save_dir,
            scripts_dir=scripts_dir,
            generated_dir=generated_sql_dir,
            timestamp=timestamp,
            ddl_source=ddl_source,
            file_extension=file_extension,
        )
    else:
        logger.error("FAIL | %s.%s | Unsupported step", schema, step)
        summary.failed_steps += 1
        return

    logger.info(
        "START | env=%s schema=%s step=%s objects=%s",
        env_name,
        schema,
        step,
        len(objects),
    )

    try:
        run_sqlplus(
            sqlplus_executable=sqlplus_executable,
            connection=connection,
            script_file=script_file,
            args=[str(save_dir)],
            cwd=project_root,
            env=subprocess_env,
            strict_mode=strict_mode,
            dry_run=dry_run,
            logger=logger,
        )
        summary.executed_steps += 1
        logger.info("DONE  | env=%s schema=%s step=%s", env_name, schema, step)
    except ExporterError:
        summary.failed_steps += 1
        logger.exception("FAIL  | env=%s schema=%s step=%s", env_name, schema, step)


def determine_strict_mode(config: dict[str, Any], args: argparse.Namespace) -> bool:
    config_value = bool(config.get("defaults", {}).get("strict_sqlplus_errors", True))

    if args.strict and args.no_strict:
        raise ExporterError("Use only one of --strict or --no-strict.")

    if args.strict:
        return True
    if args.no_strict:
        return False
    return config_value


def validate_steps(steps: list[str], env_name: str, schema: str) -> list[str]:
    normalized: list[str] = []
    for step in steps:
        step_value = normalize_step_alias(str(step))
        if step_value not in VALID_STEPS:
            raise ExporterError(
                f"Environment {env_name}, schema {schema}: unsupported step '{step_value}'."
            )
        normalized.append(step_value)
    return normalized


def scan_exported_artifacts_for_errors(
    *,
    export_root: Path,
    project_root: Path,
    max_findings: int,
    allowed_extensions: set[str],
    logger: logging.Logger,
) -> tuple[int, list[tuple[Path, int, str]], bool]:
    if max_findings <= 0:
        raise ExporterError("--post-check-max-findings must be greater than 0.")

    if not export_root.exists():
        return 0, [], False

    files_scanned = 0
    findings: list[tuple[Path, int, str]] = []

    for file_path in sorted(export_root.rglob("*")):
        if not file_path.is_file():
            continue
        if allowed_extensions and file_path.suffix.lower() not in allowed_extensions:
            continue

        files_scanned += 1

        try:
            with file_path.open("r", encoding="utf-8", errors="ignore") as handle:
                for line_no, line in enumerate(handle, start=1):
                    if POST_EXPORT_ERROR_PATTERN.search(line):
                        findings.append((file_path, line_no, line.strip()))
                        if len(findings) >= max_findings:
                            logger.warning(
                                "POST-CHECK | Reached max findings (%s), stopping scan early.",
                                max_findings,
                            )
                            return files_scanned, findings, True
        except OSError as exc:
            rel = file_path
            try:
                rel = file_path.relative_to(project_root)
            except ValueError:
                pass
            logger.warning("POST-CHECK | Could not read %s (%s)", rel, exc)

    return files_scanned, findings, False


def write_post_check_report(
    *,
    report_path: Path,
    project_root: Path,
    findings: list[tuple[Path, int, str]],
    truncated: bool,
) -> None:
    lines: list[str] = [
        "UNIVERSAL_EXPORTER post-check report",
        "",
        f"findings={len(findings)}",
        f"truncated={'yes' if truncated else 'no'}",
        "",
        "Details:",
    ]

    for file_path, line_no, text in findings:
        rel = file_path
        try:
            rel = file_path.relative_to(project_root)
        except ValueError:
            pass
        lines.append(f"- {rel}:{line_no} | {text}")

    lines.append("")
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()

    if args.task_env and not args.task_name:
        raise ExporterError("task_env argument requires task_name.")
    if args.task_schema and not args.task_name:
        raise ExporterError("task_schema argument requires task_name.")
    if args.task_name and args.envs:
        raise ExporterError("Do not mix task mode positional ENV with --env option.")

    if getattr(sys, "frozen", False):
        project_root = Path(sys.executable).resolve().parent
    else:
        project_root = Path(__file__).resolve().parent

    config_path = resolve_path(project_root, args.config)
    config = load_config(config_path)

    timestamp = args.timestamp or current_timestamp()

    logs_dir = resolve_path(project_root, str(config.get("defaults", {}).get("logs_dir", "logs")))
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_file = logs_dir / f"export_{timestamp}.log"

    logger = configure_logger(log_file, verbose=args.verbose)
    logger.info("RUN START | timestamp=%s", timestamp)
    logger.info("CONFIG    | %s", config_path)

    defaults = config.get("defaults", {})
    environments = config.get("environments", {})
    catalog = config.get("catalog", {})
    output_cfg = config.get("output", {})

    if not isinstance(environments, dict) or not environments:
        raise ExporterError("Config key 'environments' must be a non-empty object.")

    sqlplus_executable = str(defaults.get("sqlplus_executable", "sqlplus")).strip()
    if not sqlplus_executable:
        raise ExporterError("defaults.sqlplus_executable must not be empty.")

    task_mode = bool(args.task_name)
    task_env_objects: dict[str, dict[str, Any]] = {}
    task_label = ""

    if task_mode:
        if not args.task_env:
            raise ExporterError(
                "Task mode requires ENV argument: oracle_exporter.exe <TASK> <ENV> [SCHEMA]."
            )

        task_objects_file, task_label = resolve_task_objects_file(
            project_root=project_root,
            defaults=defaults,
            task_name=str(args.task_name),
            task_root_override=args.task_root,
            task_objects_file_override=args.task_objects_file,
        )
        parsed_task_envs = parse_task_objects_file(task_objects_file)
        task_env_name = str(args.task_env).strip().upper()
        task_env_objects = parsed_task_envs.get(task_env_name, {})

        if not task_env_objects:
            raise ExporterError(
                f"Task '{task_label}' objects file does not define environment [{task_env_name}]."
            )

        logger.info("TASK MODE | task=%s", task_label)
        logger.info("TASK MODE | objects=%s", task_objects_file)
        logger.info("TASK MODE | env=%s", task_env_name)

    output_root = resolve_path(project_root, str(defaults.get("output_root", "EXPORTED_OBJECTS")))
    if task_mode:
        output_root = output_root / task_label
    scripts_dir = resolve_path(project_root, str(defaults.get("scripts_dir", "scripts")))
    generated_sql_dir = logs_dir / "generated_sql" / timestamp
    generated_sql_dir.mkdir(parents=True, exist_ok=True)

    strict_mode = determine_strict_mode(config, args)
    if task_mode:
        selected_envs = [str(args.task_env).strip().upper()]
    else:
        selected_envs = normalize_list(args.envs) or list(environments.keys())

    selected_schemas = set(normalize_list(args.schemas))
    if task_mode and args.task_schema:
        task_schema = str(args.task_schema).strip().upper()
        if task_schema:
            selected_schemas.add(task_schema)

    post_check_enabled = bool(defaults.get("post_export_scan_enabled", True))
    if args.skip_post_check:
        post_check_enabled = False

    base_subprocess_env = os.environ.copy()
    default_nls_lang = str(defaults.get("nls_lang", "")).strip()
    if default_nls_lang:
        base_subprocess_env["NLS_LANG"] = default_nls_lang

    effective_default_extensions = dict(DEFAULT_EXPORT_EXTENSIONS)
    effective_default_extensions.update(
        parse_export_extensions(defaults.get("export_extensions"), "defaults")
    )
    configured_post_check_extensions = {
        ext
        for ext in (
            normalize_extension(value)
            for value in effective_default_extensions.values()
        )
        if ext
    }

    summary = RunSummary()
    processed_envs: list[str] = []

    for env_name_raw in selected_envs:
        env_name = env_name_raw.upper()
        env_config = environments.get(env_name)
        if env_config is None:
            logger.error("SKIP ENV | Environment not found in config: %s", env_name)
            summary.failed_steps += 1
            continue

        if not isinstance(env_config, dict):
            logger.error("SKIP ENV | Invalid environment config type: %s", env_name)
            summary.failed_steps += 1
            continue

        env_subprocess_env = base_subprocess_env.copy()
        task_nls_lang = ""
        if task_mode:
            task_nls_lang = str(task_env_objects.get("nls_lang", "")).strip()

        env_nls_lang = str(
            args.nls_lang
            or task_nls_lang
            or env_config.get("nls_lang", default_nls_lang)
        ).strip()
        if env_nls_lang:
            env_subprocess_env["NLS_LANG"] = env_nls_lang
        else:
            env_subprocess_env.pop("NLS_LANG", None)

        effective_extensions = dict(effective_default_extensions)
        effective_extensions.update(
            parse_export_extensions(env_config.get("export_extensions"), f"environments.{env_name}")
        )
        configured_post_check_extensions.update(
            {
                ext
                for ext in (
                    normalize_extension(value)
                    for value in effective_extensions.values()
                )
                if ext
            }
        )

        if args.dry_run:
            try:
                connection = resolve_connection_string(project_root, env_name, env_config)
            except ExporterError as exc:
                connection = "DRY_RUN_CONNECTION"
                logger.warning(
                    "DRY-RUN | Could not resolve connection for %s (%s). Using placeholder.",
                    env_name,
                    exc,
                )
        else:
            try:
                connection = resolve_connection_string(project_root, env_name, env_config)
            except ExporterError:
                logger.exception("SKIP ENV | Could not resolve connection for %s", env_name)
                summary.failed_steps += 1
                continue

        if task_mode:
            raw_task_objects = task_env_objects.get("export_objects", {})
            if not isinstance(raw_task_objects, dict):
                logger.error("SKIP ENV | Invalid export_objects structure in task file for %s", env_name)
                summary.failed_steps += 1
                continue
            env_export_objects = raw_task_objects
        else:
            env_export_objects = parse_environment_export_objects(env_name, env_config)

        schema_steps = env_config.get("schema_steps", {})

        if task_mode and selected_schemas:
            missing_schemas = selected_schemas.difference(set(env_export_objects.keys()))
            if missing_schemas:
                logger.error(
                    "SKIP ENV | Requested schema(s) not found in task file for %s: %s",
                    env_name,
                    ", ".join(sorted(missing_schemas)),
                )
                summary.failed_steps += 1
                continue

        ddl_source = str(env_config.get("ddl_source", defaults.get("ddl_source", "all"))).strip().lower()
        if ddl_source not in VALID_DDL_SOURCES:
            logger.error(
                "SKIP ENV | Invalid ddl_source for %s: %s (allowed: %s)",
                env_name,
                ddl_source,
                ", ".join(sorted(VALID_DDL_SOURCES)),
            )
            summary.failed_steps += 1
            continue

        logger.info("ENV START | %s", env_name)
        processed_envs.append(env_name)

        if env_export_objects:
            for schema_name, step_to_objects in env_export_objects.items():
                if selected_schemas and schema_name not in selected_schemas:
                    continue

                for step in STEP_PRIORITY:
                    objects_for_step = step_to_objects.get(step, [])
                    if not objects_for_step:
                        continue

                    execute_step(
                        env_name=env_name,
                        schema=schema_name,
                        step=step,
                        catalog=catalog,
                        objects_override=objects_for_step,
                        output_root=output_root,
                        output_cfg=output_cfg,
                        scripts_dir=scripts_dir,
                        generated_sql_dir=generated_sql_dir,
                        connection=connection,
                        sqlplus_executable=sqlplus_executable,
                        subprocess_env=env_subprocess_env,
                        strict_mode=strict_mode,
                        dry_run=args.dry_run,
                        timestamp=timestamp,
                        project_root=project_root,
                        ddl_source=ddl_source,
                        file_extension=effective_extensions[step],
                        logger=logger,
                        summary=summary,
                    )
        elif task_mode:
            logger.error("SKIP ENV | No export_objects configured in task file for %s", env_name)
            summary.failed_steps += 1
            continue
        else:
            if not isinstance(catalog, dict):
                raise ExporterError("Config key 'catalog' must be a mapping when schema_steps mode is used.")

            if not isinstance(schema_steps, dict) or not schema_steps:
                logger.warning(
                    "SKIP ENV | No export_objects or schema_steps configured for %s",
                    env_name,
                )
                summary.skipped_steps += 1
                continue

            for schema_name_raw, steps_raw in schema_steps.items():
                schema_name = str(schema_name_raw).strip().upper()
                if selected_schemas and schema_name not in selected_schemas:
                    continue

                if not isinstance(steps_raw, list) or not steps_raw:
                    logger.warning("SKIP | %s | schema has no steps", schema_name)
                    summary.skipped_steps += 1
                    continue

                steps = validate_steps(steps_raw, env_name, schema_name)

                for step in steps:
                    execute_step(
                        env_name=env_name,
                        schema=schema_name,
                        step=step,
                        catalog=catalog,
                        objects_override=None,
                        output_root=output_root,
                        output_cfg=output_cfg,
                        scripts_dir=scripts_dir,
                        generated_sql_dir=generated_sql_dir,
                        connection=connection,
                        sqlplus_executable=sqlplus_executable,
                        subprocess_env=env_subprocess_env,
                        strict_mode=strict_mode,
                        dry_run=args.dry_run,
                        timestamp=timestamp,
                        project_root=project_root,
                        ddl_source=ddl_source,
                        file_extension=effective_extensions[step],
                        logger=logger,
                        summary=summary,
                    )

        logger.info("ENV DONE  | %s", env_name)

    if not args.dry_run and post_check_enabled:
        logger.info("POST-CHECK START | scanning exported artifacts for ORA/SP2/PLS/TNS signatures")
        all_findings: list[tuple[Path, int, str]] = []
        total_scanned_files = 0
        truncated = False

        for env_name in processed_envs:
            remaining = args.post_check_max_findings - len(all_findings)
            if remaining <= 0:
                truncated = True
                break

            env_root = output_root / env_name / timestamp
            scanned_files, findings, scan_truncated = scan_exported_artifacts_for_errors(
                export_root=env_root,
                project_root=project_root,
                max_findings=remaining,
                allowed_extensions=configured_post_check_extensions,
                logger=logger,
            )
            total_scanned_files += scanned_files
            all_findings.extend(findings)
            if scan_truncated or len(all_findings) >= args.post_check_max_findings:
                truncated = True
                break

        summary.post_check_scanned_files = total_scanned_files
        summary.post_check_findings = len(all_findings)

        if all_findings:
            logger.error(
                "POST-CHECK FAIL | findings=%s scanned_files=%s",
                len(all_findings),
                total_scanned_files,
            )
            for file_path, line_no, text in all_findings[:20]:
                rel = file_path
                try:
                    rel = file_path.relative_to(project_root)
                except ValueError:
                    pass
                logger.error("POST-CHECK HIT | %s:%s | %s", rel, line_no, text)

            report_path = logs_dir / f"post_check_{timestamp}.txt"
            write_post_check_report(
                report_path=report_path,
                project_root=project_root,
                findings=all_findings,
                truncated=truncated,
            )
            logger.error("POST-CHECK REPORT | %s", report_path)
        else:
            logger.info(
                "POST-CHECK OK | findings=0 scanned_files=%s",
                total_scanned_files,
            )
    elif args.dry_run:
        logger.info("POST-CHECK SKIP | dry-run mode")
    else:
        logger.info("POST-CHECK SKIP | disabled by configuration or CLI")

    logger.info(
        "RUN END   | total=%s executed=%s skipped=%s failed=%s post_check_scanned=%s post_check_findings=%s",
        summary.total_steps,
        summary.executed_steps,
        summary.skipped_steps,
        summary.failed_steps,
        summary.post_check_scanned_files,
        summary.post_check_findings,
    )
    logger.info("LOG FILE  | %s", log_file)

    return 1 if summary.failed_steps > 0 or summary.post_check_findings > 0 else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ExporterError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
