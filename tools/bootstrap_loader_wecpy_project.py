#!/usr/bin/env python3
"""Generate a local WEC-Py project binding from explicit loader slice docs."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_WEC_PY_ROOT = Path("/Users/kikbot/Documents/Playground/WEC-Py")
DEFAULT_PLANNING_ROOT = WORKSPACE_ROOT / "design" / "planning"
DEFAULT_OUTPUT_ROOT = WORKSPACE_ROOT / "runtime_data" / "wecpy"
PHASE_DOC_PATTERN = "WARDEN4_Phase_*_v1.md"
SLICE_DOC_PATTERN = "WARDEN4_IMPLEMENTATION_SLICE_P*_v1.md"
SLICE_NAME_PATTERN = re.compile(
    r"^WARDEN4_IMPLEMENTATION_SLICE_P(?P<phase>\d+)_T(?P<task>\d+)_S(?P<slice>\d+)_(?P<slug>.+?)_v1\.md$"
)
PHASE_DOC_NAME_PATTERN = re.compile(r"^WARDEN4_Phase_(?P<phase>\d+?)_(?P<slug>.+?)_v1\.md$")


def _load_wec_py_modules(wec_py_root: Path):
    source_root = wec_py_root / "src"
    if str(source_root) not in sys.path:
        sys.path.insert(0, str(source_root))
    from wec_py_mcp.pem_generator import generate_pems
    from wec_py_mcp.profiles import create_profile_registry
    from wec_py_mcp.project_encoding import load_project_encoding
    from wec_py_mcp.runtime_state import StateStore, create_initial_runtime_state
    from wec_py_mcp.orchestrator import create_orchestrator

    return {
        "create_profile_registry": create_profile_registry,
        "generate_pems": generate_pems,
        "load_project_encoding": load_project_encoding,
        "StateStore": StateStore,
        "create_initial_runtime_state": create_initial_runtime_state,
        "create_orchestrator": create_orchestrator,
    }


def _normalize_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _parse_plain_sections(text: str) -> dict[str, list[str]]:
    known_headers = {
        "Objective",
        "Claim",
        "Parent Phase",
        "Parent Track",
        "Changes In Scope",
        "Explicit Out Of Scope",
        "Verification",
        "Evidence",
        "Closure Condition",
        "Follow-On",
        "Entry Gate",
        "Controlling Canon",
        "Tracks And Slice Register",
        "Exit Gate",
        "Live Test Gate",
        "Relationship To Other Planning Docs",
    }
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for raw_line in text.splitlines()[1:]:
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            if current is not None:
                sections.setdefault(current, []).append("")
            continue
        if stripped in known_headers:
            current = stripped
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections.setdefault(current, []).append(line)
    return sections


def _extract_first_paragraph(lines: list[str]) -> str:
    collected: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if collected:
                break
            continue
        if stripped.startswith("- "):
            if collected:
                break
            continue
        collected.append(stripped)
    return _normalize_whitespace(" ".join(collected))


def _extract_bullets(lines: list[str]) -> list[str]:
    values: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- "):
            values.append(_normalize_whitespace(stripped[2:]))
    return values


def parse_phase_docs(planning_root: Path) -> dict[int, dict[str, str]]:
    phase_map: dict[int, dict[str, str]] = {}
    for path in sorted(planning_root.glob(PHASE_DOC_PATTERN)):
        match = PHASE_DOC_NAME_PATTERN.match(path.name)
        if not match:
            continue
        phase_num = int(match.group("phase"))
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        heading = lines[0].strip() if lines else path.stem
        sections = _parse_plain_sections(text)
        phase_map[phase_num] = {
            "title": re.sub(r"^WARDEN4\s+Phase\s+\d+\s+", "", heading).strip(),
            "objective": _extract_first_paragraph(sections.get("Objective", []))
            or f"Execute loader phase {phase_num:02d}.",
            "source_path": str(path),
        }
    return phase_map


def parse_slice_doc(path: Path, order: int) -> dict[str, Any]:
    match = SLICE_NAME_PATTERN.match(path.name)
    if not match:
        raise ValueError(f"unsupported slice filename: {path.name}")
    phase_num = int(match.group("phase"))
    task_num = int(match.group("task"))
    task_slice_num = int(match.group("slice"))
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    heading = lines[0].strip() if lines else path.stem
    sections = _parse_plain_sections(text)
    title = re.sub(r"^WARDEN4\s+Implementation\s+Slice\s+P\d+\.T\d+\.S\d+\s+", "", heading).strip()
    title = re.sub(r"\s+v\d+$", "", title).strip()
    objective = _extract_first_paragraph(sections.get("Objective", []))
    claim = _extract_first_paragraph(sections.get("Claim", []))
    closure_condition_lines = [
        line
        for line in sections.get("Closure Condition", [])
        if _normalize_whitespace(line) != "This slice closes when:"
    ]
    acceptance_criteria = _extract_bullets(closure_condition_lines)
    if not acceptance_criteria:
        acceptance_criteria = [claim or objective or title]
    return {
        "order": order,
        "phase_num": phase_num,
        "task_num": task_num,
        "task_slice_num": task_slice_num,
        "title": title,
        "objective": objective or claim or f"Implement {title}.",
        "acceptance_criteria": acceptance_criteria,
        "source_path": str(path),
        "metadata": {
            "original_locator": f"P{phase_num}.T{task_num}.S{task_slice_num}",
            "source_heading": heading,
            "claim": claim,
            "parent_phase": _extract_bullets(sections.get("Parent Phase", [])),
            "parent_track": _extract_bullets(sections.get("Parent Track", [])),
        },
    }


def _task_title(task_slices: list[dict[str, Any]], phase_num: int, task_num: int) -> str:
    first = task_slices[0]
    track = first.get("metadata", {}).get("parent_track") or []
    if track:
        return track[0]
    return f"Phase {phase_num:02d} Task {task_num:02d}"


def _task_objective(task_title: str, task_slices: list[dict[str, Any]]) -> str:
    return (
        f"Execute the bounded slice set for {task_title}. "
        f"Start with {task_slices[0]['objective']}"
    )


def build_project_payload(
    planning_root: Path,
    output_root: Path,
    *,
    corpus_id: str,
    corpus_version: str,
) -> dict[str, Any]:
    phase_docs = parse_phase_docs(planning_root)
    slice_docs = [parse_slice_doc(path, index) for index, path in enumerate(sorted(planning_root.glob(SLICE_DOC_PATTERN)), start=1)]
    phase_task_map: dict[tuple[int, int], list[dict[str, Any]]] = {}
    phase_numbers: set[int] = set()
    for slice_doc in slice_docs:
        phase_numbers.add(slice_doc["phase_num"])
        phase_task_map.setdefault((slice_doc["phase_num"], slice_doc["task_num"]), []).append(slice_doc)

    phases_payload: list[dict[str, Any]] = []
    previous_phase_id: str | None = None
    for phase_num in sorted(phase_numbers):
        task_entries = [
            (task_num, phase_task_map[(phase_num, task_num)])
            for task_num in sorted(task_num for p, task_num in phase_task_map if p == phase_num)
        ]
        phase_id = f"phase-{phase_num:03d}"
        tasks_payload: list[dict[str, Any]] = []
        previous_task_id: str | None = None
        for task_num, task_slices in task_entries:
            task_id = f"task-{len(tasks_payload)+1:03d}"
            task_payload: dict[str, Any] = {
                "task_id": task_id,
                "title": _task_title(task_slices, phase_num, task_num),
                "objective": _task_objective(_task_title(task_slices, phase_num, task_num), task_slices),
                "task_class": "coding",
                "dependencies": [previous_task_id] if previous_task_id else [],
                "loop_profile_binding": {"profile_id": "coding_slice", "version": "0.2.0"},
                "skill_profile_binding": {"profile_id": "coding_skills", "version": "0.2.0"},
                "inputs": [slice_doc["source_path"] for slice_doc in task_slices],
                "acceptance_criteria": [
                    f"Complete the bounded slice set for {_task_title(task_slices, phase_num, task_num)}.",
                    "Do not advance without explicit user live-test confirmation.",
                ],
                "policy_overrides": {},
                "slices": [],
            }
            previous_slice_id: str | None = None
            for slice_doc in task_slices:
                slice_id = f"slice-{slice_doc['order']:03d}"
                task_payload["slices"].append(
                    {
                        "slice_id": slice_id,
                        "title": slice_doc["title"],
                        "objective": slice_doc["objective"],
                        "dependencies": [previous_slice_id] if previous_slice_id else [],
                        "inputs": [slice_doc["source_path"]],
                        "acceptance_criteria": slice_doc["acceptance_criteria"],
                        "metadata": {
                            **slice_doc["metadata"],
                            "phase_id": phase_id,
                            "task_id": task_id,
                            "phase_num": phase_num,
                            "task_num": task_num,
                            "live_test_required": True,
                            "advance_requires_user_confirmation": True,
                        },
                        "policy_overrides": {
                            "closeout_policy_ref": "task_closeout_policy",
                        },
                    }
                )
                previous_slice_id = slice_id
            tasks_payload.append(task_payload)
            previous_task_id = task_id
        phases_payload.append(
            {
                "phase_id": phase_id,
                "title": phase_docs.get(phase_num, {}).get("title", f"Phase {phase_num:02d}"),
                "objective": phase_docs.get(phase_num, {}).get("objective", f"Execute phase {phase_num:02d}."),
                "dependencies": [previous_phase_id] if previous_phase_id else [],
                "tasks": tasks_payload,
            }
        )
        previous_phase_id = phase_id

    return {
        "schema_version": "0.2.0",
        "project_id": "warden4-local-llm-loader-rebuild",
        "project_name": "WARDEN4 Local LLM Loader Rebuild",
        "project_root": str(output_root),
        "project_type": "subsystem",
        "corpus_binding": {
            "binding_version": "0.2.0",
            "corpus_id": corpus_id,
            "corpus_version": corpus_version,
            "corpus_location": str(planning_root),
            "adapter_id": "local_markdown_corpus",
            "ruleset_scope": "project",
            "severity_policy_ref": "default_severity",
            "conflict_policy_ref": "default_conflict",
        },
        "policy_bindings": {
            "permission_policy_ref": "local_safe_permission_policy",
            "acceptance_policy_ref": "strict_acceptance_policy",
            "review_policy_ref": "standard_review_policy",
            "retry_policy_ref": "bounded_retry_policy",
            "closeout_policy_ref": "task_closeout_policy",
        },
        "registry_requirements": {
            "loop_profile_registry_version_range": ">=0.2.0,<0.3.0",
            "skill_profile_registry_version_range": ">=0.2.0,<0.3.0",
            "corpus_adapter_registry_version_range": ">=0.2.0,<0.3.0",
        },
        "work_graph": {"phases": phases_payload},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate loader WEC-Py execution artifacts from explicit slice docs.")
    parser.add_argument("--planning-root", default=str(DEFAULT_PLANNING_ROOT))
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--wec-py-root", default=str(DEFAULT_WEC_PY_ROOT))
    parser.add_argument("--corpus-id", default="warden4-local-llm-loader-slices")
    parser.add_argument("--corpus-version", default="0.1.0")
    args = parser.parse_args()

    planning_root = Path(args.planning_root)
    output_root = Path(args.output_root)
    modules = _load_wec_py_modules(Path(args.wec_py_root))
    registry = modules["create_profile_registry"]()
    payload = build_project_payload(
        planning_root,
        output_root,
        corpus_id=args.corpus_id,
        corpus_version=args.corpus_version,
    )

    encoding_path = output_root / "wec_loop_planning_slice.project.encoding.json"
    runtime_state_path = output_root / "runtime.state.json"
    pems_dir = output_root / "authoritative-pems"
    encoding_path.parent.mkdir(parents=True, exist_ok=True)
    encoding_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    review_findings_path = output_root / "wec_loop_planning_slice.project.encoding.json.review-findings.json"
    review_findings_path.write_text(json.dumps({"finding_count": 0, "findings": []}, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    project_encoding = modules["load_project_encoding"](encoding_path, registry)
    runtime_state = modules["create_initial_runtime_state"](
        project_encoding,
        encoding_ref=f"{encoding_path.name}@{project_encoding.schema_version}",
    )
    modules["StateStore"](runtime_state_path).save(runtime_state)
    generated_pems = modules["generate_pems"](project_encoding, pems_dir)
    decision = modules["create_orchestrator"](registry).select_next_slice(project_encoding, runtime_state)
    ordered_slice_ids = [item.slice_id for item in generated_pems]
    summary = {
        "encoding_path": str(encoding_path),
        "review_findings_path": str(review_findings_path),
        "runtime_state_path": str(runtime_state_path),
        "pems_dir": str(pems_dir),
        "phase_count": len(project_encoding.work_graph.phases),
        "task_count": sum(len(phase.tasks) for phase in project_encoding.work_graph.phases),
        "slice_count": sum(len(task.slices) for phase in project_encoding.work_graph.phases for task in phase.tasks),
        "pem_count": len(generated_pems),
        "next_slice_id": decision.candidate.slice_id if decision.candidate else None,
        "next_pem_id": generated_pems[ordered_slice_ids.index(decision.candidate.slice_id)].pem_id if decision.candidate else None,
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
