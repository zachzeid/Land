# Integrating local LLMs (Ollama and alternatives) into Land (Godot 4.5.1)

Research date: 2026-11-02. Latest Ollama on GitHub at that date: **v0.40.13** (28 Oct 2026, marked Latest), with **v0.40.14-rc0** (3 Nov) as a pre-release — [Ollama releases](https://github.com/ollama/ollama/releases). Third-party release summaries disagree on version numbering, so use the GitHub releases page as the authority — [fazm.ai summary](https://fazm.ai/t/ollama-release-notes-2026), [PromptQuorum](https://www.promptquorum.com/local-llms/top-open-source-models-ollama).

## Ollama REST API: /api/chat vs /api/generate vs /v1/chat/completions, streaming, options, think, tools

### Takeaway
Use native **`/api/chat`**. It is the only endpoint that exposes every relevant control per request: `format` (JSON schema), `think`, `keep_alive`, and `options.num_ctx`. The OpenAI-compatible `/v1/chat/completions` cannot set `num_ctx` per request, which matters because a 2-3.2k-token system prompt plus history exceeds the 4096-token default. Streaming is newline-delimited JSON (NDJSON) and is on by default; the final chunk carries `done: true` and the timing stats.

### Cited Findings
- The API docs are moving: "Ollama's API docs are moving to https://docs.ollama.com/api". `docs/api.md` still lists the fields below — [ollama docs/api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **`/api/chat` request fields:** `model` (required), `messages`, `tools`, `think`, `format` (`"json"` or a JSON schema), `options`, `stream`, `keep_alive` (default `5m`). Message objects have `role` (`system`/`user`/`assistant`/`tool`), `content`, `thinking`, `images`, `tool_calls` and `tool_name` — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **`/api/chat` response fields:** `model`, `created_at`, `message`, `done`, `done_reason`, `total_duration`, `load_duration`, `prompt_eval_count`, `prompt_eval_duration`, `eval_count`, `eval_duration` — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **`/api/generate`** takes `prompt`, `suffix`, `images`, `system`, `template`, `raw`, `format`, `options`, `stream`, `keep_alive` and `think`. Its `context` field is **deprecated**. Its response adds `prompt_eval_cached_count`, which shows how many prompt tokens came from cache — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **Streaming:** "Streaming is the default. Each chunk is a JSON object, and the final object has `"done": true` along with the statistics." Set `"stream": false` to get a single object — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **Option names** (a full list is in the Modelfile docs): `num_keep`, `seed`, `num_predict`, `draft_num_predict`, `top_k`, `top_p`, `min_p`, `repeat_last_n`, `temperature`, `repeat_penalty`, `presence_penalty`, `frequency_penalty`, `penalize_newline`, `stop`, `numa`, `num_ctx`, `num_batch`, `num_gpu`, `main_gpu`, `use_mmap`, `num_thread`. `typical_p` is deprecated — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **Defaults:** "By default, Ollama uses a context window size of 4096 tokens." Override it server-wide with `OLLAMA_CONTEXT_LENGTH` or per request with `options.num_ctx` — [Ollama FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- **`keep_alive`:** models stay loaded for 5 minutes by default. The value can be a duration string ("10m"), a number of seconds, a negative number (keep loaded indefinitely) or `0` (unload right after the response). The per-request `keep_alive` overrides `OLLAMA_KEEP_ALIVE`. To preload, send a request with only the model, e.g. `curl http://localhost:11434/api/chat -d '{"model": "mistral"}'`, optionally with `"keep_alive": -1` — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- **Binding and CORS:** the server binds `127.0.0.1:11434` by default (`OLLAMA_HOST` changes it). Cross-origin requests from 127.0.0.1 and 0.0.0.0 are allowed by default; `OLLAMA_ORIGINS` adds more — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- **`think` parameter:** accepts `true`, `false`, `null` or a string level; "Numbers are not supported." `false` requests no thinking "if the model permits it", and `null` uses the model default. String levels come from `thinking.values` in `/api/show` (gpt-oss shows `"low"`, `"medium"` and `"high"`, default `"medium"`); "Unsupported names use the model default." If `/api/show` returns `values: [false]`, the model does not think. Chat returns `message.thinking` and `message.content`; generate returns `thinking` and `response`. When streaming, thinking tokens arrive before content tokens — [Ollama thinking docs](https://docs.ollama.com/capabilities/thinking)
- `api.md` also lists `think` levels `"low"`, `"medium"`, `"high"` and `"max"` for `/api/generate` — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **OpenAI-compatible `/v1/chat/completions`** supports `model`, `messages`, `stream`, `temperature`, `top_p`, `stop`, `seed`, `max_tokens`, `frequency_penalty`, `presence_penalty`, `tools`, `response_format`, `stream_options.include_usage` and `reasoning_effort` ("model-defined names and compatibility aliases"). It does **not** support `tool_choice`, `logit_bias`, `user`, `n`, logprobs or image URLs. "The OpenAI API does not have a way of setting the context size for a model." The workaround is a Modelfile with `PARAMETER num_ctx <context size>` built via `ollama create` — [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- **Recent OpenAI-compatibility fixes:** v0.40.14-rc0 fixes "preserving Responses input content and not overriding model sampler defaults". v0.40.9 makes streaming OpenAI Responses and **Anthropic Messages** requests report generation failures, which means Ollama now exposes an Anthropic-Messages-compatible surface. v0.40.7 adds `renderer`, `parser` and `template_source` API fields — [Ollama releases](https://github.com/ollama/ollama/releases)
- **Tool calling:** `/api/chat` takes `tools`; the model replies with `message.tool_calls`; the result goes back as a `role: "tool"` message with `tool_name` — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md). Over `/v1`, `tool_choice` is unsupported, so you cannot force a tool call — [OpenAI compat](https://docs.ollama.com/api/openai-compatibility)

### Inferences
- **Easiest port from the Claude client:** keep the HTTPRequest/HTTPClient code and change the URL to `http://127.0.0.1:11434/api/chat`. Move the system prompt into `messages[0]` with `role: "system"` (Claude sends it as a top-level `system` field), and send `format: <schema>`, `think: false`, `stream: false`, `keep_alive: -1` and `options: {num_ctx: 8192, temperature: ...}` on every request. Non-streaming is simplest for strict-JSON turns, because a partial JSON object cannot be shown to the player anyway.
- **Streaming in Godot (not sourced; standard Godot API):** `HTTPClient` lets you poll `read_response_body_chunk()` and split the buffer on `\n`. Each complete line is one JSON object to pass to `JSON.parse_string`. Keep the trailing partial line until the next chunk arrives. Streaming only pays off if the `response` text is shown before `analysis` finishes. With a JSON schema, the `response` field's text arrives first only if it is the first property, so put `response` first in the schema.
- Use `think: false` for NPC turns, so reasoning models do not spend latency on hidden tokens. But see the bugs below on how `think` interacts with `format`. A non-reasoning model avoids the problem entirely.
- Use `tools` for the `actions` array only if the model handles tool calls well. A JSON-schema `actions` array is more deterministic, matches the existing contract and avoids the missing `tool_choice`.

### Gaps
- I did not fetch the full Modelfile valid-parameters table, so per-option defaults are not listed here.
- I did not confirm from the docs whether `response_format: {type: "json_schema", ...}` on `/v1` enforces the schema exactly as native `format` does. The structured-outputs page only says structured outputs work "through the OpenAI-compatible API, using `response_format`".
- I did not fetch the Godot HTTPClient docs. The streaming notes above come from general knowledge of the Godot 4 API.

## Structured outputs (`format` with a JSON schema): reliability, enum/nested/array support, speed, bugs

### Takeaway
On GGUF models, `format: <JSON schema>` is enforced by constrained decoding. It is the right mechanism for Land's `{response, analysis{enums, int deltas}, actions[], commitments}` contract. Several 2026 bugs matter: the **MLX engine silently ignores `format`**, and Gemma 4 has had `format` dropped depending on the `think` setting. Always validate on the Godot side and retry, because a failure can come back as HTTP 200.

### Cited Findings
- **Usage:** "Provide a JSON schema to the `format` field." "It is ideal to also pass the JSON schema as a string in the prompt." The docs suggest temperature `0` for deterministic output. Structured output works over `/v1` via `response_format`. "Ollama's cloud currently does not support structured outputs." The page does not document which JSON Schema keywords are supported — [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- Nested structures, including a list of objects, are a documented use case — [structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- **Issue #8063:** schema violations, with `const` and `enum` reportedly not honored — [ollama#8063](https://github.com/ollama/ollama/issues/8063). This is an older issue (opened around Dec 2024) and may be outdated; the summary I read did not confirm its current status.
- **Issue #15260:** `think=false` broke `format` for gemma4, and the constraint was silently ignored. It was fixed by #15678, which issue #17183 says shipped in **v0.21.1** — [ollama#15260](https://github.com/ollama/ollama/issues/15260), [ollama#17183](https://github.com/ollama/ollama/issues/17183)
- **Issue #18774 (reported on v0.35.1, open per search results):** Gemma 4 does not enforce the JSON schema when `think:true` and the model answers without emitting reasoning — [ollama#18774](https://github.com/ollama/ollama/issues/18774)
- **MLX backend ignores `format`:** reported in #16563, #17013 (closed as a duplicate), #17183 (gemma4:12b-mlx, qwen3.5:0.8b-mlx; "GGUF builds honour it") and #17933 ("format and response_format both no-op; invalid response_format returns 200"; constrained decoding appears unimplemented on MLX) — [#16563](https://github.com/ollama/ollama/issues/16563), [#17013](https://github.com/ollama/ollama/issues/17013), [#17183](https://github.com/ollama/ollama/issues/17183), [#17933](https://github.com/ollama/ollama/issues/17933)
- Ollama has been investing heavily in MLX on Apple silicon: faster MLX prompt processing for Gemma 4, Flint and Laguna, DFlash speculative decoding on MLX (v0.40.12), and chunked top-k sorting in MLX (v0.40.14-rc0). None of the notes I read says MLX constrained decoding has been fixed — [releases](https://github.com/ollama/ollama/releases)
- LM Studio warns that "not all models are capable of structured output, particularly LLMs below 7B parameters" — [LM Studio structured output](https://lmstudio.ai/docs/app/api/structured-output)

### Inferences
- **On the M4 dev Mac, use GGUF model tags, not `-mlx` tags.** The MLX tags are faster, but they would silently drop the schema and produce free text that breaks the parser.
- Keep the schema shallow, put `required` on every key, and set `additionalProperties: false`. Validate enums and integer ranges in GDScript anyway, since enum enforcement has a reported bug history (#8063). Retry once with temperature lowered on a parse or validation failure.
- **Speed cost:** I found no primary measurement of grammar or schema overhead in Ollama. Constrained decoding mainly adds per-token sampling overhead; prompt processing is unaffected.
- Using a non-thinking model, or `think: false` on a recent build (>= v0.21.1), avoids the #15260 and #18774 class of bugs.

### Gaps
- No authoritative list of the JSON Schema keywords Ollama supports (`minimum`/`maximum`, `pattern`, `oneOf`, etc.).
- No benchmark of tokens/s with versus without `format`.
- I could not confirm whether #8063 (enum/const) is fixed on v0.40.x.

## Performance: concurrency, KV/prompt cache reuse, TTFT on Apple Silicon vs NVIDIA, flash attention, KV quantization, context defaults

### Takeaway
By default Ollama serves one request at a time per model (`OLLAMA_NUM_PARALLEL=1`) and queues up to 512 more. Each parallel slot multiplies KV memory by `num_ctx`. Prefix reuse only happens while the model stays loaded with an **unchanged `num_ctx`**; changing `num_ctx` forces a full reload. On a base M4 (10-core GPU), prefill for a 7B Q4 model is about 220 tok/s, so a cold 3,000-token prompt takes roughly 13-14 s to the first token. A cache hit, or a mid-range NVIDIA GPU at several thousand tok/s, brings that down to well under a second.

### Cited Findings
- `OLLAMA_NUM_PARALLEL`: "The maximum number of parallel requests each model will process at the same time, default 1." Required RAM "will scale by `OLLAMA_NUM_PARALLEL` * `OLLAMA_CONTEXT_LENGTH`". For example, a 2K context with 4 parallel requests becomes 8K — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- `OLLAMA_MAX_LOADED_MODELS`: "The default is 3 * the number of GPUs or 3 for CPU inference." On a GPU, a new model must fully fit in VRAM to load alongside others. Windows with Radeon GPUs defaults to 1 model maximum — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- `OLLAMA_MAX_QUEUE`: default 512. Requests beyond the limit get a 503 — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- **Flash attention:** "Ollama uses Flash Attention automatically when the selected backend and devices support it." `OLLAMA_FLASH_ATTENTION=1` forces it on and `=0` disables it — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- **`OLLAMA_KV_CACHE_TYPE`:** default `f16`. `q8_0` uses about half the memory with "very small" precision loss and is the FAQ's recommendation if you move off f16. `q4_0` uses about a quarter, with small-to-medium loss that is more noticeable at long context. It applies only when flash attention is on, it is **global** to all models, and high-GQA models such as Qwen2 may be affected more — [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)
- **Changing `num_ctx` reloads the model:** the KV cache is allocated at load time, so a different `num_ctx` tears the model down and reloads it. One author measured about 140 s per reload for a 26B model on an RTX 5090 (blog, not official). The advice is to pin one `num_ctx` value — [dev.to "reload tax"](https://dev.to/pat9000/pin-your-context-window-or-pay-the-reload-tax-3nfo), [bmdpat blog](https://bmdpat.com/blog/pin-num-ctx-local-llm-reload-tax-2026), [SSD Nodes](https://www.ssdnodes.com/learn/ollama-context-length-num-ctx)
- The KV prefix cache is only reused while the model stays loaded. Send the same `num_ctx` on every request and use a long `keep_alive`. A request-level `num_ctx` overrides the server default — [Leanpub Ollama book, Prompt Caching](https://leanpub.com/read/ollama/prompt-caching), [SSD Nodes](https://www.ssdnodes.com/learn/ollama-context-length-num-ctx) (secondary sources)
- `/api/generate` responses include `prompt_eval_cached_count`, which you can use to check cache hits — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **Apple M4 llama.cpp benchmarks (LLaMA 7B, t/s, commit 8e672ef):**

  | Chip | GPU cores | Q4_0 pp512 | Q4_0 tg128 | Q8_0 pp512 | Q8_0 tg128 |
  |---|---|---|---|---|---|
  | M4 | 10 | 221.29 | 24.11 | 223.64 | 13.54 |
  | M4 Pro | 16 | 364.06 | 49.64 | 367.13 | 30.54 |
  | M4 Pro | 20 | 439.78 | 50.74 | 449.62 | 30.69 |
  | M4 Max | 32 | 713.93 | 69.95 | 718.56 | 43.87 |
  | M4 Max | 40 | 885.68 | 83.06 | 891.94 | 54.05 |

  For comparison, a commenter's 2x RTX 3090 result for 7B Q4_0 was pp512 1178.60 and tg128 87.34, on a different build — [llama.cpp discussion #4167](https://github.com/ggml-org/llama.cpp/discussions/4167)
- **RTX 4090, Qwen3-8B Q4_K_M prefill:** about 9,250 tok/s at 4k context per one summary, but hardware-corner's table and text disagree (6,721 vs 2,572 tok/s at 16k). Treat these as unreliable — [smeltcore](https://smeltcore.com/recipes/qwen3-8b-on-rtx-4090-q4-k-m-gguf-via-ollama-or-llama-cpp/), [hardware-corner](https://www.hardware-corner.net/gpu-ranking-local-llm/)
- **Generation:** about 24 tok/s for qwen3.5:9b on a 16 GB M4 MacBook Pro versus about 128 tok/s on an RTX 4090 — [computingforgeeks](https://computingforgeeks.com/ollama-models-cheat-sheet/)

### Inferences
- **Cold time-to-first-token on the M4 dev machine:** about 3,000 tokens / 220 tok/s ≈ **13-14 s** for a 7-8B model, and roughly 2.5× faster for a 3-4B model. This is extrapolated from the pp512 numbers; prefill speed drops further at longer context. Prefix caching is therefore critical.
- **Keep the cacheable part identical byte-for-byte.** Put the static NPC system prompt first, append history, and put volatile state (time, mood, location) **last**. Anything that changes early in the prompt invalidates every token after it.
- **106 NPCs on one parallel slot means NPCs evict each other's prefix.** After a switch, each NPC's first turn pays the full prefill. Options:
  - Raise `OLLAMA_NUM_PARALLEL` to 2-4 so a few hot NPCs keep their own slots. The KV cost is about `num_parallel × num_ctx`; whether a request is routed back to the slot holding its prefix is not documented.
  - Use llama-server's explicit `id_slot` and `--cache-ram`, covered in the alternatives section.
- **Memory on 32 GB:** an 8B Q4 model (~5 GB) plus 8k context × 4 slots with `q8_0` KV fits comfortably. Set `num_ctx` once, around 6-8k, since 3.2k of system prompt plus history plus JSON output exceeds the 4096 default.
- Run agent-decision calls (`{choice, effects, reason}`) with a small `num_predict` and a minimal system prompt, so they are cheap.
- On consumer NVIDIA GPUs, prefill is an order of magnitude faster. The player experience is bounded mostly by the Mac/low-end tier.

### Gaps
- Ollama does not document how parallel slots are matched to cached prefixes, or whether a multi-slot cache exists beyond the KV of each loaded slot.
- No primary M4 prefill measurement for current models (Qwen3/Gemma 4) through Ollama. Run `ollama run --verbose` and read the "prompt eval rate" line to measure it.
- No measured MLX-engine prefill numbers. The engine is faster per the release notes, but `format` is broken on it.

## Embeddings: /api/embed, models, ChromaDB OllamaEmbeddingFunction, switching an existing collection

### Takeaway
`/api/embed` takes a batch `input` and returns `embeddings`. Chroma ships an `OllamaEmbeddingFunction(url=..., model_name=...)`. The existing Land collection was built with Chroma's default embedder (all-MiniLM-L6-v2, 384-dim). Switching models makes the collection incompatible: newer Chroma persists the embedding function and raises a conflict error. Re-embed all documents into a **new collection** named by model.

### Cited Findings
- **`/api/embed` request:** `model`; `input` (a string, a list of strings, or objects with `text`/`image`/`audio`); `truncate` (default `true`; `false` returns an error when context is exceeded); `dimensions`; `keep_alive`; `options`. Response: `model`, `embeddings`, `total_duration`, `load_duration`, `prompt_eval_count`. `/api/embeddings` is superseded — [api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)
- **`/v1/embeddings`** supports `model`, `input` (string or array of strings), encoding format and `dimensions`, but not token-array inputs or `user` — [OpenAI compat](https://docs.ollama.com/api/openai-compatibility)
- **Chroma usage:** `from chromadb.utils.embedding_functions.ollama_embedding_function import OllamaEmbeddingFunction`, then `OllamaEmbeddingFunction(url="http://localhost:11434", model_name="...")`. A TypeScript package `@chroma-core/ollama` also exists — [Chroma Ollama integration](https://docs.trychroma.com/integrations/embedding-models/ollama)
- "Chroma's default embedding function uses the Sentence Transformers all-MiniLM-L6-v2 model," which runs locally and may download model files. Custom embedding functions implement `get_config` and `build_from_config` — [Chroma embedding functions](https://docs.trychroma.com/docs/embeddings/embedding-functions)
- **Switching embedders** gives an error like "Embedding function conflict: new: X vs persisted: Y". Chroma persists the embedding-function metadata with the collection and refuses a different one. Fixes: use the same embedding function, delete or recreate the collection, or keep one collection per embedding model. Loading without an embedding function can cause dimension mismatches — [CrewAI community](https://community.crewai.com/t/unable-to-change-model-provider-for-mdxsearchtool/7367), [fixdevs](https://fixdevs.pages.dev/blog/chromadb-not-working/), [itsourcecode](https://itsourcecode.com/valueerror/chromadb-invalid-dimension-exception-fix/) (informal sources; behavior varies by Chroma version)

### Inferences
- **Migration:** in `chroma_cli.py`, add a `--embedder ollama:<model>` mode that creates `npc_memory__<model>` and re-adds every document, reading the old collection with its original embedding function. Then switch reads over. Never mix vectors in one collection.
- **Model choice (from general knowledge; not verified this session):**
  - nomic-embed-text: 768-dim, small.
  - mxbai-embed-large: 1024-dim.
  - bge-m3: multilingual, 1024-dim.
  - embeddinggemma: about 300M parameters, supports Matryoshka truncation via `dimensions`.
  - qwen3-embedding: 0.6B / 4B / 8B.

  For short NPC memories, nomic-embed-text or embeddinggemma is enough. Keeping the current MiniLM default in Chroma avoids running a second model in Ollama altogether.
- An embedding model and a chat model loaded together count toward `OLLAMA_MAX_LOADED_MODELS` (default 3 per GPU), which is fine.

### Gaps
- I did not retrieve official model pages for nomic-embed-text, mxbai-embed-large, bge-m3, embeddinggemma and qwen3-embedding, so their dimensions and context sizes above are unverified.
- The Chroma docs I read do not document the conflict error. The sources for it are community posts.
- I did not confirm whether `OllamaEmbeddingFunction` needs the `ollama` Python package or accepts a `timeout` argument.

## Alternatives for development and shipping: NobodyWho, godot-llm, llama-server, LM Studio, MLX, vLLM; licensing and distribution

### Takeaway
- **Development:** Ollama, or llama-server for finer cache control.
- **Shipping:** NobodyWho is the most mature in-process Godot option. It supports JSON schema, GBNF/Lark grammars and regex constraints, tool calling and embeddings, and runs on Vulkan or Metal. Its current docs say it **requires Godot 4.6+**, so Land on 4.5.1 would need an engine upgrade or an older NobodyWho release. Its license is EUPL-1.2.
- **llama-server** as a bundled sidecar is the alternative: MIT, explicit slots, `json_schema`, a RAM prompt cache and slot save/restore.
- **Not suitable:** godot-llm looks stale (last push June 2024), and vLLM is a datacenter tool.

### Cited Findings
- **NobodyWho platforms and backends:** Godot runs on Desktop and Android; Godot has no iOS export, there is no web export (#111), and Windows ARM64 is unsupported. GPU acceleration uses Vulkan or Metal, and CUDA appears in the architecture diagram; without a Vulkan driver it falls back to CPU. Models are GGUF only, referenced as `hf:owner/repo:QUANT`, a URL or a local path, and are "downloaded and cached on first use"; `"auto"` fits a model to available memory.
  - License: **EUPL-1.2** — "You may use it in proprietary and commercial projects, free of charge", but modified versions of the library's own code must be open-sourced.
  - Source: [NobodyWho GitHub](https://github.com/nobodywho-ooo/nobodywho)
- **NobodyWho Godot setup:** "Requires Godot 4.6 or newer." Install by copying `addons/nobodywho` from a release; it bundles Windows, Linux, macOS and Android libraries. Recommended hardware is 4 CPU cores and 8 GB RAM, with Vulkan optional. The docs versions span 9.3.0–13.0.0.
  - API: `await NobodyWhoChat.create(model_path, {...})`, `chat.ask(prompt)` returns a stream, and `await stream.completed()` gives the final text.
  - Async methods return `null` on failure.
  - Source: [NobodyWho Godot docs](https://docs.nobodywho.ooo/godot/)
- The NobodyWho main docs page still says "GDExtension for Godot 4.x", which is less specific. The Asset Library entry is asset 2886 — [NobodyWho docs home](https://docs.nobodywho.ooo/). (Conflicts with the 4.6+ requirement above; the Godot page is more specific.)
- **NobodyWho structured output in GDScript:** `NobodyWhoSamplerPresets.constrain_with_json_schema(JSON.stringify(schema))`, `constrain_with_regex("yes|no")` and `constrain_with_grammar(grammar)`, which accepts Lark or GBNF (GBNF is converted to Lark). There is also a builder: `NobodyWhoSamplerBuilder.new().json_schema(schema_dict).temperature(0.8).dist()`, with `.regex()`, `.lark()` and `.json()`. Constraints always run first. Sampler settings can be saved and changed with `chat.get_sampler_config()`, `chat.set_sampler_config(...)` and `NobodyWhoSamplerConfig.from_json()`. The JSON schema is called a "hard guarantee", but the supported schema keywords are not listed.
  - Source: [NobodyWho Sampling](https://docs.nobodywho.ooo/godot/sampling)
- **NobodyWho Godot subpages:** tool calling (lets the model call GDScript functions), embeddings & RAG, decision models, STT (Whisper), TTS and VAD — [NobodyWho Godot docs](https://docs.nobodywho.ooo/godot/). Decision models are also a new Ollama model family ("d3 decision models in 2B to 27B sizes", v0.40.11) — [Ollama releases](https://github.com/ollama/ollama/releases)
- **godot-llm (Adriankhl):** MIT. Backends are Windows (CPU, Vulkan), macOS (CPU, Metal; "best-effort"), Linux (CPU, Vulkan) and Android (CPU). Nodes include `GdLlama` and `GdEmbedding`, with simple RAG. One aggregator reports the last push was 23 Jun 2024, with 241 stars — **likely outdated or unmaintained** — [godot-llm](https://github.com/Adriankhl/godot-llm), [ecosyste.ms](https://awesome.ecosyste.ms/projects/github.com%2Fadriankhl%2Fgodot-llm)
- **"Godot Llama"** is a separate Asset Library entry described as a native llama.cpp GDExtension targeting Godot 4.5. I did not examine it — [Asset Library 4810](https://godotengine.org/asset-library/asset/4810)
- **llama.cpp `llama-server`:**
  - **Slots:** `-np/--parallel N` (default -1 = auto); continuous batching (`-cb`) is on by default. `-kvu/--kv-unified` gives one shared KV buffer and is on when parallel is auto; `--kv-unified-per-slot N` caps each slot. `id_slot` on `/completion` pins a request to a slot.
  - **KV cache types:** `-ctk`/`-ctv` (f16 default; q8_0, q4_0, etc.).
  - **Prompt cache:** `--cache-prompt` (on), `--cache-reuse N` (KV-shift reuse, default 0), and `-cram/--cache-ram N` (a RAM prompt cache in MiB, default 8192). `--cache-idle-slots` saves idle slots into that cache.
  - **Slot save/restore:** `--slot-save-path`, then `POST /slots/{id}?action=save|restore|erase` saves KV state to disk.
  - **Constrained output:** `json_schema` and `grammar` (GBNF) on `/completion`; `response_format` with a `schema` on `/v1/chat/completions`.
  - **Other flags:** `-fa auto` (flash attention), `--jinja` (chat templates), `GET /slots`, and `/embedding(s)` with `--pooling`.
  - Caveat: `cache_prompt` can make logits differ across batch sizes, so results may be nondeterministic.
  - Source: [llama-server README](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md)
- **LM Studio:** `/v1/chat/completions` with `response_format.json_schema`. For MLX models, structured output uses Outlines (lmstudio-ai/mlx-engine) — [LM Studio structured output](https://lmstudio.ai/docs/app/api/structured-output)

### Inferences
- **Development (M4):**
  - **Ollama with GGUF models** is the fastest route: one install, the current HTTP code barely changes, and `/api/chat` with `format`, `keep_alive: -1` and a fixed `num_ctx` covers the contract.
  - **LM Studio** is a reasonable GUI alternative, and it gives schema-enforced MLX via Outlines. That may make it the better MLX option on Mac, since Ollama's MLX engine ignores `format`.
- **Per-NPC prompt cache:** llama-server's `--cache-ram` together with `id_slot`, or slot save/restore to disk, is the strongest way to keep the 20 main NPCs' system-prompt KV warm. Ollama does not expose this control.
- **Shipping to players:**
  1. **NobodyWho in-process.** No separate server; Vulkan/Metal cover Windows, Linux and Mac. Its schema sampler matches Land's JSON contract. It requires Godot 4.6+ according to current docs, so check whether an older release supports 4.5. EUPL-1.2 is permissive for using it unmodified; modifying the addon obliges you to publish those changes.
  2. **Bundled `llama-server` sidecar** (MIT), launched via `OS.create_process`. This keeps the existing HTTPRequest client and the cache controls. You must ship per-platform builds (CUDA, Vulkan, Metal).
  3. **Requiring players to install Ollama.** The most friction for players; best as an optional "advanced" backend.
- **Model download size:** about 2-5 GB for a 3-8B Q4 GGUF. Download it on first run rather than bundling it in the game build. NobodyWho's `hf:` download with caching supports this.
- **Licensing:** Ollama is MIT and llama.cpp is MIT (general knowledge; I did not fetch the license files this session). Model weights carry their own licenses (Gemma terms, Llama community license, Apache-2.0 for Qwen and Mistral small models), so check each model's license before redistributing.

### Gaps
- I did not research the mlx-lm server (`mlx_lm.server`) or vLLM in detail. vLLM is CUDA/server-oriented and unsuitable for consumer distribution (general knowledge, unsourced).
- I found no documented commercial game that ships a local LLM through any of these paths, so that question is unanswered. NobodyWho's own examples or showcase page may list some.
- I did not verify the Ollama and llama.cpp license files or the exact model-weight license terms this session.
- I did not confirm whether a NobodyWho release that supports Godot 4.5.1 exists, or which version it would be.
