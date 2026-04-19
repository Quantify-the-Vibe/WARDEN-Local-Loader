# Integration Notes For pi-mono

## Document Status

- status: canonical spec-input
- purpose: define the client boundary for the next implementation spec

## Working Frame

- `pi-mono` is the first client
- `pi-mono` is not the loader authority model
- `pi-mono` should integrate through the loader boundary, not through MLX internals

## Ownership Boundary

Loader owns:

- local model discovery
- load and reset lifecycle
- active runtime ownership
- structured runtime state
- backend adapter selection
- backend subprocess handling
- memory admission and reclaim policy once implemented

`pi-mono` owns:

- chat UX
- prompt composition UX
- response display
- deciding when to call the loader

## Implemented Connection Path

Implemented now:

- canonical loader control surface on `:8787`
- OpenAI-compatible bridge on `:8080/v1/chat/completions`
- current `pi-mono` connection path is the OpenAI-compatible bridge

## Integration Rule

- `:8080` exists to let `pi-mono` connect with minimal friction
- `:8080` must not become the source of loader policy truth
- canonical loader semantics remain defined by the loader-owned control model, not by `pi-mono` expectations

## Current Bridge Behavior

Implemented now:

- accepts `POST /v1/chat/completions`
- supports streaming-compatible SSE framing
- normalizes model IDs like `mlx-community/Qwen2.5-0.5B-Instruct-4bit`
- bridge default is translation-only and does not auto-load
- requires explicit canonical load on `:8787` before bridge generation
- returns `explicit_load_required` when load precondition is missing
- optional legacy auto-load is feature-flag constrained (`W4L_OPENAI_BRIDGE_AUTOLOAD`)
- applies tokenizer chat template when available
- falls back to structured prompt formatting for models without tokenizer chat templates

Known limitations:

- helper still generates whole responses, not true token streaming
- bridge exists for compatibility, not for full OpenAI semantics
- tool-calling semantics are not a loader goal
- long multi-turn behavior is not yet optimized as a first-class loader concern

## Required Constraints For Next Spec

The next implementation spec should preserve these:

- `pi-mono` must not own backend-specific startup details
- `pi-mono` must not parse model directories from disk
- `pi-mono` must not directly manage MLX helper processes
- product-level prompt rewriting remains outside loader authority
- product-level output rewriting remains outside loader authority

## Questions The Next Spec Must Resolve

- should legacy auto-load flag remain available, or be removed in v0.4
- what structured error envelope should `pi-mono` expect for admission failure
- how memory budget failures surface on the bridge
- whether bridge responses should expose budget warnings or only hard failures
- whether a second compatibility route is needed later, or whether `:8080` is sufficient

## Explicit Non-Goals

- making the loader a `pi-mono` plugin
- letting `pi-mono` define backend lifecycle policy
- adding `pi-mono`-specific behavior to the backend adapter seam
- turning compatibility behavior into canonical authority without an explicit decision
