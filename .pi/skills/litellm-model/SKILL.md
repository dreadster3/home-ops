---
name: litellm-model
description: Add, enable, disable, or update LLM models in the LiteLLM proxy running in the home-ops Kubernetes cluster. Use whenever the user wants to add a new model to LiteLLM, enable a model (like "enable claude-opus-5"), disable or remove a model, update model pricing, swap one model for another, set up a fallback chain, add a routing alias, or check/verify model costs from models.dev. Triggers on phrases like "add model to litellm", "enable <model>", "disable <model>", "update litellm model", "litellm model pricing", "swap <old> for <new>", "add fallback for <model>", "register <model> in litellm". Always use this skill for LiteLLM model_list changes — do not edit the HelmRelease blind.
---

# LiteLLM Model Skill

Add, enable, disable, update, or swap models in the LiteLLM proxy's
`model_list`. The proxy config lives in a HelmRelease; every model entry is a
YAML block with a `model_info` (costs + limits) and `litellm_params` (provider
routing). This skill makes those edits precise, consistent, and
price-verified.

## Where everything lives

- **Config file:** `kubernetes/apps/base/litellm/helm.yaml`
  - `proxy_config.model_list` — one block per model (the model registry)
  - `router_settings.model_group_alias` — clean alias → primary `model_name`
  - `router_settings.fallbacks` — ordered fallback chains per alias
- **API keys / env:** `kubernetes/apps/base/litellm/secrets.yaml` — the
  `litellm-secret-env` ExternalSecret maps Infisical keys → env vars consumed
  by `api_key: os.environ/<NAME>` in `litellm_params`.
- **Dev overlay:** `kubernetes/apps/overlays/dev/litellm/` — patches replica
  count and PG cluster only; it does **not** override the model list. Model
  changes in base apply to all environments.
- **Project root:** the repo with `DECISION.md`. A new provider or a
  cost-tier change for a flagship model qualifies as a decision — see the
  decision-log skill.

## The two facts that govern every edit

1. **`model_name` is the LiteLLM-facing identifier** (what clients call). It
   is usually `<provider>/<model-id>`, e.g. `anthropic/claude-opus-5`.
   `litellm_params.model` is what LiteLLM sends to the upstream provider —
   usually the same string, but for Ollama Cloud it is `openai/<model-id>`
   with `api_base: https://ollama.com/v1` (OpenAI-compatible gateway).
2. **`model_info` costs are per-token, not per-million.** models.dev lists
   prices per 1M tokens; divide by 1,000,000. `$5/M` → `0.000005`.

## Canonical model block — the template every entry follows

```yaml
- model_name: <provider>/<model-id> # LiteLLM-facing name
  # <source note>: <ctx / out>, $<in>/M in, $<out>/M out, cache_read $<X>/M, cache_write $<Y>/M
  model_info:
    mode: chat # chat | responses | image_generation | audio_speech | audio_transcription | embedding
    max_input_tokens: <int> # from models.dev limit.context (or limit.input)
    max_output_tokens: <int> # from models.dev limit.output
    supports_vision: <true|false> # models.dev attachment
    supports_reasoning: <true|false> # models.dev reasoning
    input_cost_per_token: 0.0 # $/M ÷ 1,000,000
    output_cost_per_token: 0.0
    cache_read_input_token_cost: 0.0 # prompt-cache read; 0 if provider has none
    cache_creation_input_token_cost: 0.0 # prompt-cache write; 0 if none
    # Optional tiers (long-context pricing):
    # input_cost_per_token_above_<N>k_tokens: 0.0
    # output_cost_per_token_above_<N>k_tokens: 0.0
    # cache_read_input_token_cost_above_<N>k_tokens: 0.0
    # cache_creation_input_token_cost_above_<N>k_tokens: 0.0
    # Optional non-token costs:
    # input_cost_per_token_batches: 0.0       # batch/off-peak rate
    # output_cost_per_token_batches: 0.0
    # input_cost_per_character: 0.0           # TTS (e.g. tts-1)
    # input_cost_per_second: 0.0             # STT (e.g. whisper-1, nova-2)
    # output_cost_per_second: 0.0
    # output_cost_per_image_token: 0.0        # image-generation output
    # output_cost_per_image: 0.0             # image-generation, per-image flat
  litellm_params:
    model: <provider>/<model-id> # upstream model string
    api_key: os.environ/<ENV_VAR> # omit for providers without a key (e.g. github_copilot)
    # api_base: <url>                        # only for OpenAI-compatible gateways (ollama cloud)
```

## Which `api_key` env var to use

| Provider prefix in `model_name` | `api_key` env var                                               | Notes                                                       |
| ------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------- |
| `anthropic/`                    | `os.environ/ANTHROPIC_API_KEY`                                  | Direct Anthropic API                                        |
| `openai/`                       | `os.environ/OPENAI_API_KEY`                                     | Direct OpenAI API (or responses API)                        |
| `gemini/`                       | `os.environ/GEMINI_API_KEY`                                     | Google AI Studio                                            |
| `deepgram/`                     | `os.environ/DEEPGRAM_API_KEY`                                   |                                                             |
| `github_copilot/`               | **omit**                                                        | OAuth device flow; token dir via `GITHUB_COPILOT_TOKEN_DIR` |
| `ollama/`                       | `os.environ/OLLAMA_API_KEY` + `api_base: https://ollama.com/v1` | `litellm_params.model` becomes `openai/<id>`                |

If a provider is new (no row in the table and no key in `secrets.yaml`),
adding the model also means: add the env var to the `litellm-secret-env`
ExternalSecret template, add the `remoteRef` data entry, and add the key to
Infisical under `/litellm/<NAME>`. Flag this to the user — it is a secret-store
change, not just a helm edit.

## How to get the numbers (models.dev)

Fetch `https://models.dev/api.json` and read the provider entry
(`anthropic`, `openai`, `github-copilot`, `ollama-cloud`, `google-vertex-anthropic`,
…). Each model has a `cost` object with `input`, `output`, `cache_read`,
`cache_write` **per 1M tokens**, plus a `limit` object with `context` and
`output`. Convert:

- `input` ($/M) → `input_cost_per_token` = value ÷ 1,000,000
- `output` ($/M) → `output_cost_per_token` = value ÷ 1,000,000
- `cache_read` ($/M) → `cache_read_input_token_cost`; `0` if absent
- `cache_write` ($/M) → `cache_creation_input_token_cost`; `0` if absent
- `limit.context` → `max_input_tokens`; `limit.output` → `max_output_tokens`
- `attachment` → `supports_vision`; `reasoning` → `supports_reasoning`
- Long-context tiers: if `cost` has `tiers` or `context_over_<N>k`, mirror them
  with the `_above_<N>k_tokens` fields (divide the tier's threshold in tokens
  by 1000 for the field suffix, e.g. 200000 → `above_200k_tokens`).

Use `ctx_execute` (shell) to fetch with `curl -s -m 20 -o /tmp/modelsdev.json`
then `python3 -c "import json; ..."` to print only the target model's JSON.
Never stream the 3 MB API dump into context — filter in code.

If models.dev lacks the model (GA release not yet indexed, or a community map
overrides), say so in the source comment and cite where the number came from
(provider pricing page, LiteLLM community map). Existing entries already do
this — match their tone.

## Operation: add a new model

1. **Resolve the facts.** Fetch models.dev, extract the provider + model entry,
   convert prices to per-token. If models.dev is silent, note the alternate
   source. If a new API key is needed, flag the `secrets.yaml` + Infisical step.
2. **Place the block** in `model_list` under the right section header. The
   file is organized by provider in this order:
   image generation → audio (TTS/STT) → embeddings → Anthropic direct →
   GitHub Copilot → OpenAI direct → Ollama Cloud. Put a fallback partner next
   to its primary (e.g. `openai/gpt-5.6-luna` fallback sits under the
   `github_copilot/gpt-5.6-luna` primary). Keep comments aligned with
   neighbors (2-space indent under the list item).
3. **Write a source comment** as the first line under `model_name`: one line,
   naming the source and the headline numbers, e.g.
   `# from models.dev (anthropic): 1M ctx / 128k out, $5/$25 per M, cache_read $0.5/M, cache_write $6.25/M`.
   If cache isn't published by the provider, say so and set those fields to
   `0.0` (see `github_copilot/gemini-3.5-flash`).
4. **Register the alias** in `router_settings.model_group_alias` if the model
   should be reachable by a short name (e.g. `claude-opus-5: anthropic/claude-opus-5`).
   Not every internal/fallback model needs an alias — fallback targets
   (like `openai/gpt-5.6-luna`) intentionally have no alias.
5. **Register a fallback chain** in `router_settings.fallbacks` if the new
   model is a primary with a direct-API twin. Format is the alias mapping to
   a list of `model_name` strings. Keep grouping aligned with neighbors.
6. **Verify YAML** — re-read the edited region; confirm indentation matches
   siblings and the `model_list` array stays valid. Do not run `kubectl` or
   Flux commands unless the user asks.

## Operation: enable an existing-but-disabled model

"Enable" usually means the upstream provider just shipped a model the user
wants to call. If the entry already exists and just needs a cost/limit bump,
follow `update`. If it's a brand-new model id, follow `add`. There is no
separate disabled flag in this config — presence in `model_list` is what
makes a model live.

## Operation: disable / remove a model

1. Delete its block from `model_list`.
2. Delete its alias from `router_settings.model_group_alias` if present.
3. Delete any fallback chain entry that references it (as primary or as a
   fallback target). If it was a fallback target for a still-live primary,
   the primary loses that fallback — tell the user.
4. Do **not** remove the env var from `secrets.yaml` unless the user asks;
   other models may share the key.

## Operation: update model pricing / limits

When a provider revises pricing (e.g. a tier change), update the
`model_info` cost fields in place and refresh the source comment's headline
numbers. Re-verify against models.dev — if the API changed its schema (new
tier key, new cost field), mirror it with the matching LiteLLM field. Keep
the per-token vs per-Mental conversion explicit in your own head: `$2/M` is
`0.000002`, not `0.0002`.

## Operation: swap one model for another

A swap is three coordinated edits, not a find-replace:

1. Replace the `model_name`, `litellm_params.model`, and `model_info` of the
   old block with the new model's facts (per the add template).
2. Update `router_settings.model_group_alias`: change the alias value from
   the old to the new `model_name`.
3. Update any `fallbacks` chain referencing the old `model_name`.
4. Leave a source comment reflecting the new model. If pricing is unchanged,
   say so (e.g. "1M ctx / 128k out, $5/$25 per M" carries over) — it's worth
   confirming against models.dev rather than assuming.

## Common mistakes to avoid

- **Per-million prices left as-is.** `$5` → `0.000005`. A misplaced decimal
  inflates Prometheus cost metrics by 1000×.
- **`max_input_tokens` from the wrong field.** models.dev's `limit.context`
  is the total window; some providers publish a smaller `limit.input` (what
  you can actually send). Use `limit.context` for Anthropic; for OpenAI
  "input cap" models use the input cap, not the context window.
- **Forgetting the fallback twin.** A subscription primary
  (`github_copilot/<x>`) without its direct-API fallback is paying for a
  safety net you don't have; both blocks must exist and both must be listed
  in `fallbacks`. (Rule 1.)
- **Forgetting the alias.** A model in `model_list` with no
  `model_group_alias` entry is unreachable by its short name — clients call
  the alias, not the `model_name`. Always create/edit the alias when adding
  or swapping, unless the model is a fallback-only target.
- **Paying for API when a subscription covers it.** Adding `anthropic/<x>`
  as a standalone primary when `github_copilot/<x>` is already on the
  subscription = per-token charges for capacity you own. Check the
  subscription providers first.
- **Ollama Cloud routing.** `model_name` is `ollama/<id>` but
  `litellm_params.model` is `openai/<id>` with `api_base: https://ollama.com/v1`
  — not `ollama/<id>`. Costs are `0.0` (Ollama Cloud bills outside LiteLLM).
- **Editing the dev overlay by reflex.** It doesn't override the model list.
  Base is the source of truth for all environments.

## Verification

After editing, re-read the three regions of `helm.yaml` that were touched
(`model_list` block, `model_group_alias`, `fallbacks`) and confirm:

- Indentation matches siblings (2-space steps).
- Every new `model_name` has a matching `litellm_params.model`.
- Every alias points at a `model_name` that exists in `model_list`.
- Every `model_name` in a `fallbacks` chain exists in `model_list`.
- Cost fields are per-token (six decimal places for $/M values).
- The source comment names where the numbers came from.

Report to the user: what was added/changed, the source of the pricing, any
secret-store or Infisical follow-up needed, and whether a `DECISION.md` entry
is warranted. Do not apply to the cluster — Flux reconciles on commit.
