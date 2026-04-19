#!/usr/bin/env python3
"""Minimal persistent MLX helper for PEM-003."""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
from pathlib import Path

from mlx_lm import generate, load


def emit(payload: dict[str, object]) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def _read_json_if_exists(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:  # noqa: BLE001
        return {}


def detect_prompt_format(model_path: Path) -> str:
    tokenizer_config = _read_json_if_exists(model_path / "tokenizer_config.json")
    model_config = _read_json_if_exists(model_path / "config.json")

    tokenizer_class = str(tokenizer_config.get("tokenizer_class", "")).lower()
    model_type = str(model_config.get("model_type", "")).lower()
    path_text = str(model_path).lower()

    if "gemma" in tokenizer_class or model_type == "gemma" or "gemma" in path_text:
        return "gemma"

    return "generic"


def build_fallback_chat_prompt(messages: list[dict[str, str]], prompt_format: str) -> str:
    normalized_messages: list[dict[str, str]] = []
    pending_system: list[str] = []

    for message in messages:
        role = str(message.get("role", "")).strip().lower()
        content = str(message.get("content", "")).strip()
        if not role or not content:
            continue

        if role in {"system", "developer"}:
            pending_system.append(content)
            continue

        normalized_messages.append({"role": role, "content": content})

    if prompt_format == "gemma":
        segments: list[str] = []
        if pending_system:
            system_prefix = "\n\n".join(pending_system)
            if normalized_messages and normalized_messages[0]["role"] == "user":
                normalized_messages[0]["content"] = f"{system_prefix}\n\n{normalized_messages[0]['content']}"
            else:
                normalized_messages.insert(0, {"role": "user", "content": system_prefix})

        for message in normalized_messages:
            role = message["role"]
            if role not in {"user", "assistant"}:
                role = "user"
            model_role = "model" if role == "assistant" else "user"
            segments.append(f"<start_of_turn>{model_role}\n{message['content']}<end_of_turn>")

        segments.append("<start_of_turn>model\n")
        return "\n".join(segments)

    generic_parts: list[str] = []
    if pending_system:
        generic_parts.append("System:\n" + "\n\n".join(pending_system))
    for message in normalized_messages:
        role = message["role"].capitalize()
        generic_parts.append(f"{role}:\n{message['content']}")
    generic_parts.append("Assistant:\n")
    return "\n\n".join(generic_parts)


def main() -> int:
    parser = argparse.ArgumentParser(description="Load one MLX model and keep the process resident.")
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--model-path", required=True)
    args = parser.parse_args()

    model_path = Path(args.model_path)
    if not model_path.is_dir():
        emit(
            {
                "status": "failed",
                "error": "model_path_not_found",
                "model_id": args.model_id,
                "model_path": str(model_path),
            }
        )
        return 2

    try:
        model, tokenizer = load(str(model_path))
    except Exception as exc:  # noqa: BLE001
        emit(
            {
                "status": "failed",
                "error": "mlx_load_failed",
                "detail": str(exc),
                "model_id": args.model_id,
                "model_path": str(model_path),
            }
        )
        return 1

    keepalive = {"running": True}

    def _stop(_: int, __) -> None:
        keepalive["running"] = False

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    emit(
        {
            "status": "ready",
            "model_id": args.model_id,
            "model_path": str(model_path),
            "pid": os.getpid(),
            "transport": "swift->python->mlx",
            "note": "MLX model loaded with default load() behavior and held resident by the helper process.",
        }
    )

    # Keep strong references alive for model residency.
    _resident = (model, tokenizer)
    while keepalive["running"]:
        line = sys.stdin.readline()
        if not line:
            break
        try:
            command = json.loads(line)
        except json.JSONDecodeError:
            emit({"status": "failed", "error": "invalid_command_json"})
            continue
        if command.get("command") == "shutdown":
            emit({"status": "stopping", "model_id": args.model_id})
            break
        if command.get("command") == "health":
            emit({"status": "ready", "model_id": args.model_id, "model_path": str(model_path)})
            continue
        if command.get("command") == "generate":
            prompt = command.get("prompt")
            if not isinstance(prompt, str) or not prompt:
                emit({"status": "failed", "error": "missing_prompt"})
                continue
            try:
                output = generate(model, tokenizer, prompt, verbose=False)
            except Exception as exc:  # noqa: BLE001
                emit(
                    {
                        "status": "failed",
                        "error": "generate_failed",
                        "detail": str(exc),
                    }
                )
                continue
            emit(
                {
                    "status": "ok",
                    "model_id": args.model_id,
                    "prompt": prompt,
                    "response": output,
                }
            )
            continue
        if command.get("command") == "generate_chat":
            messages = command.get("messages")
            if not isinstance(messages, list) or not messages:
                emit({"status": "failed", "error": "missing_messages"})
                continue
            try:
                if getattr(tokenizer, "chat_template", None):
                    prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
                else:
                    prompt = build_fallback_chat_prompt(messages, detect_prompt_format(model_path))
                output = generate(model, tokenizer, prompt, verbose=False)
            except Exception as exc:  # noqa: BLE001
                emit(
                    {
                        "status": "failed",
                        "error": "generate_chat_failed",
                        "detail": str(exc),
                    }
                )
                continue
            emit(
                {
                    "status": "ok",
                    "model_id": args.model_id,
                    "response": output,
                }
            )
            continue
        emit({"status": "failed", "error": "unsupported_command", "command": command.get("command")})

    _ = _resident
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
