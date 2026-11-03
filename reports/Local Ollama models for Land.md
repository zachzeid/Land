# Cache the prompt to make local NPCs work

Land can replace Claude and ElevenLabs with local models today. The thing that decides whether it feels responsive is how long the model takes to read the prompt, not which model you pick. On the developer's 32 GB Apple M4, which is most likely the base 10-GPU-core chip, llama.cpp reads a prompt at about **221 tokens/s** for a 7B model. A cold 3,000-token NPC system prompt therefore waits **about 13-14 s** before the first word. A cached prompt prefix brings that under a second, and a 24 GB NVIDIA card reads the same prompt cold in about 1 s ([llama.cpp #4167](https://github.com/ggml-org/llama.cpp/discussions/4167), [hardware-corner](https://www.hardware-corner.net/gpu-llm-benchmarks/rtx-3090/)).

The recommended stack has four parts:

- **Development.** Ollama (current release v0.40.13; at least 0.31.2 is required), using **GGUF model tags, not MLX tags**. Call native `/api/chat` with a full JSON-schema `format`, `think: false`, a fixed `num_ctx` of about 8192 and `keep_alive: -1`. Lay every prompt out with static content first, so the prefix can be cached.
- **Models.** A Qwen3.5/Gemma 4-generation model sized to the player's hardware tier. Agent decisions run on the same model or on a 2-4B model, constrained by an enum schema.
- **Voice.** **Kokoro-82M** (Apache-2.0) is the default TTS: a Kokoro-FastAPI sidecar during development, and an in-engine ONNX build for shipping. **Chatterbox-Turbo** (MIT) is an optional expressive tier.
- **Memory.** Keep ChromaDB's current MiniLM embedder unless retrieval quality is measurably the problem.

Ollama is the right development tool but the wrong thing to ask players to install. For shipping, use a bundled `llama-server` sidecar (MIT), or the NobodyWho addon once Land moves to Godot 4.6+. The two biggest risks are silent failures, where Ollama returns HTTP 200 while ignoring the schema, and the memory budget on 16-32 GB machines that also run the game and TTS.

## Reading the prompt, not generating the reply, is the latency bottleneck on Macs

Every NPC turn has two costs: reading the prompt (prefill) and generating the reply (decode). On Apple Silicon, prefill dominates. The llama.cpp benchmarks below are from an old 2023 build, so treat them as a floor, but they show the shape: prompt reading roughly doubles from M4 to M4 Pro and doubles again to M4 Max ([llama.cpp #4167](https://github.com/ggml-org/llama.cpp/discussions/4167)). Decode on the base M4 runs at about **24 tok/s for qwen3.5:9b**, against about **128 tok/s on an RTX 4090** ([computingforgeeks](https://computingforgeeks.com/ollama-models-cheat-sheet/)).

Land's turns produce about 120-180 output tokens: the spoken line plus the `analysis`/`actions` JSON. At 24 tok/s that is 6-9 s of decode for a 9B dense model on the dev machine, even with a perfect cache hit. That is too slow for snappy conversation. A 4B model, or a mixture-of-experts (MoE) model with only 3-4B parameters active per token, roughly halves that time.

| Hardware | Prompt read, 7B Q4 (tok/s) | Decode, 7B Q4 (tok/s) | Cold 3k-token prompt to first token |
|---|---|---|---|
| M4, 10 GPU cores (likely the dev box) | 221 | 24 | about 13-14 s |
| M4 Pro, 20 GPU cores | 440 | 51 | about 7 s |
| M4 Max, 40 GPU cores | 886 | 83 | about 3.5 s |
| RTX 3090, 30B-class MoE | about 3,000-3,600 | 119-150 | about 1 s |

Sources: Apple rows from [llama.cpp #4167](https://github.com/ggml-org/llama.cpp/discussions/4167); RTX 3090 row from [hardware-corner](https://www.hardware-corner.net/gpu-llm-benchmarks/rtx-3090/) and [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6). The first-token times are arithmetic from those rates, not measurements.

Because prefill dominates, prompt caching is something the architecture depends on, not an optimisation. Ollama reuses the cached work for a matching prompt prefix only while the model stays loaded with an **unchanged `num_ctx`**. The KV cache (the model's stored working state for the tokens it has already read) is allocated when the model loads. Changing `num_ctx` between requests therefore reloads the whole model. One author measured about 140 s per reload for a 26B model ([dev.to](https://dev.to/pat9000/pin-your-context-window-or-pay-the-reload-tax-3nfo)).

Ollama's default context window is **4,096 tokens**, which is smaller than Land's 3.2k-token prompts plus history and output. Pin the context once, at about 8,192 tokens, either per request or with `OLLAMA_CONTEXT_LENGTH` ([Ollama FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)). Then order each prompt so the cache can hit:

1. Shared world rules and the effect menu.
2. The NPC's soul.
3. History.
4. Volatile state last: time, mood, location and retrieved memories.

Any change early in the prompt invalidates every cached token after it. Prewarming an NPC's prefix when the player walks toward them hides most of the remaining cost. `prompt_eval_cached_count` in the response shows whether the cache actually hit ([api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)).

With roughly 106 NPCs, a single slot means each conversation evicts the previous NPC's prefix. Ollama serves one request per model by default (`OLLAMA_NUM_PARALLEL=1`). Memory grows with parallel slots × context length ([FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)), and Ollama does not document whether a request goes back to the slot that holds its prefix. llama-server has the controls Ollama lacks ([llama-server README](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md)):

- `id_slot` pins a request to a specific slot;
- a RAM prompt cache (`--cache-ram`, 8 GiB by default);
- per-slot KV save and restore to disk (`/slots/{id}?action=save|restore`).

Those controls would let all 20 main NPCs keep a warm prefix. For Land, that matters more than any difference between models. Two memory settings also help ([FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx)):

- `OLLAMA_KV_CACHE_TYPE=q8_0` halves KV memory with "very small" precision loss.
- Flash attention turns on automatically where the hardware supports it.

## Ollama's `/api/chat` fits Land's JSON contract, with three silent-failure traps

The port from the Claude client is small. Keep the existing HTTPRequest code, point it at `http://127.0.0.1:11434/api/chat`, and move the system prompt into `messages[0]` with `role: "system"`. Then send these fields on every request:

- `format`: Land's JSON schema;
- `think: false`;
- `stream`;
- `keep_alive`;
- `options.num_ctx`.

Native `/api/chat` is the right endpoint because it accepts every one of those fields per request ([api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)). The OpenAI-compatible `/v1/chat/completions` cannot set the context size ("The OpenAI API does not have a way of setting the context size") and does not support `tool_choice` ([Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)). Release notes show Ollama now also has an Anthropic-Messages-compatible surface ([releases](https://github.com/ollama/ollama/releases)). It is tempting as a near drop-in replacement for the Claude client, but it inherits the same context-size problem. Use it only for a quick first test.

Streaming is newline-delimited JSON (one JSON object per line), and the final chunk carries `done: true` plus timing stats ([api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)). In Godot, poll `HTTPClient.read_response_body_chunk()` and split the buffer on newlines. Streaming only helps if the `response` field is the **first property** in the schema, so its text, and the TTS for its first sentence, can start before the `analysis` block finishes.

`format` with a JSON schema is the right way to enforce `{response, analysis{enums, int deltas}, actions[], commitments}`. On GGUF models it uses constrained decoding, which masks invalid tokens as they are generated. Nested objects and arrays are a documented use case. The docs advise also pasting the schema into the prompt, and Ollama ignores property `description` fields ([Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs), [makandracards](https://makandracards.com/makandra/626409-ollama-structured-input-output)).

Three traps make validation in Godot mandatory:

1. **The MLX engine ignores `format`.** Ollama's MLX engine (Apple's machine-learning framework, used for `-mlx` model tags) silently ignores both `format` and `response_format`, and returns HTTP 200 even for an invalid schema ([#17183](https://github.com/ollama/ollama/issues/17183), [#17933](https://github.com/ollama/ollama/issues/17933)). On the M4, `-mlx` tags are faster and would quietly break the parser. Use GGUF tags only.
2. **Thinking mode has broken the schema.** For most of 2026, setting `think: false` on Qwen3.5/3.6 made Ollama drop the grammar. It waited for an end-of-thinking token that never came, so the model returned free text. The fix was confirmed in **0.31.2 (July 2026)** ([#14645](https://github.com/ollama/ollama/issues/14645)). A related Gemma 4 bug, where the schema is not enforced when `think: true` and the model emits no reasoning, is reported open on 0.35.1 ([#18774](https://github.com/ollama/ollama/issues/18774)).
3. **Enum handling has a bug history.** An older issue reports `enum` and `const` not being honoured ([#8063](https://github.com/ollama/ollama/issues/8063)); its current status is unconfirmed.

The safe configuration is Ollama ≥ 0.31.2, non-thinking mode, and a shallow schema with `required` on every key and `additionalProperties: false`. In GDScript, validate the enums, clamp the integer deltas, and retry once at a lower temperature if parsing fails. Set `num_predict` high enough for the whole object, because a cutoff mid-object produces invalid JSON even under a grammar.

Avoid gpt-oss for strict schemas until it has been tested: its reasoning traces leak into the output and break parsing ([Glukhov](https://www.glukhov.org/post/2025/10/ollama-gpt-oss-structured-output-issues/)). Thinking should be off for NPC turns anyway, because hidden reasoning tokens would use up the latency budget.

### Three ways to put a model inside the shipped game

Requiring players to install Ollama works as an "advanced" backend, but it is too much friction for the default. That leaves two realistic shipping paths.

**NobodyWho** is the most mature in-process Godot addon ([GitHub](https://github.com/nobodywho-ooo/nobodywho), [Godot docs](https://docs.nobodywho.ooo/godot/), [sampling docs](https://docs.nobodywho.ooo/godot/sampling)):

- It runs GGUF models on Vulkan or Metal, with CPU fallback.
- It enforces JSON schemas, GBNF/Lark grammars and regexes through `NobodyWhoSamplerPresets.constrain_with_json_schema`.
- It also covers tool calling, embeddings, Whisper speech-to-text and TTS.
- It can download a model on first run (`hf:` sources, cached).
- Its license is EUPL-1.2: free for proprietary use, but changes to the addon's own code must be published.

The blocker is that its current docs say it **requires Godot 4.6 or newer**. Land is on 4.5.1.

**A bundled `llama-server` sidecar** (MIT) starts with `OS.create_process`. It keeps Land's HTTP client and adds the slot and cache controls described above ([llama-server README](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md)). The cost is shipping separate CUDA, Vulkan and Metal builds.

godot-llm is not a viable third option: its last push was June 2024 ([ecosyste.ms](https://awesome.ecosyste.ms/projects/github.com%2Fadriankhl%2Fgodot-llm)).

The choice comes down to whether Land will upgrade the engine. If it will, NobodyWho collapses LLM, embeddings and Kokoro TTS into one addon. If not, llama-server is the shorter path from today's code.

## Qwen3.5 and Gemma 4 are the 2026 models to test; MoE models suit 24 GB cards

The current open models in range are:

- **Qwen3.5** (Mar 2026; 0.8B to 35B-A3B on Ollama) ([Ollama library](https://ollama.com/library/qwen3.5));
- **Qwen3.6-35B-A3B** (Apr 2026, Apache-2.0) ([HF](https://huggingface.co/Qwen/Qwen3.6-35B-A3B));
- **Gemma 4** (E2B, E4B, 26B-A4B MoE and 31B dense; Apache-2.0 at every size, unlike Gemma 3's custom terms) ([The Register](https://www.theregister.com/2026/04/02/googles_gemma_4_open_weights/));
- **Ministral 3** 3B/8B/14B (Apache-2.0) ([eWEEK](https://www.eweek.com/news/mistral-3-launch/));
- **gpt-oss-20B**.

Llama 3.x, Phi-4, Mistral NeMo and the DeepSeek-R1 distills are a generation older. Most community role-play fine-tunes, such as Rocinante and Cydonia, are built on those older NeMo and Mistral Small bases. Recommendations for them come from low-quality SEO guides ([Aliteq](https://aliteq.com/best-local-llm-for-creative-writing-roleplay-2026)).

The MoE models suit 24 GB cards: they generate at near small-model speed but need 17-22 GB for weights. On an RTX 4090, Gemma 4 26B-A4B decodes at about **164 tok/s** and Qwen3.6 35B-A3B at about **161 tok/s**, while the dense Gemma 4 31B manages only 44 ([RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)). Most of these figures are community aggregates mixing engines, so treat them as approximate.

| Player tier | Dialogue model | Agent-decision model | Notes |
|---|---|---|---|
| 8 GB GPU / 16 GB Mac | Qwen3.5 4B (3.3-4.0 GB), Gemma 4 E4B, Ministral 3 3B | Same model, or Qwen3.5 0.8B/2B | One model for both jobs saves memory |
| 12 GB GPU / 24 GB Mac | Qwen3.5 9B (6.6-7.6 GB), Ministral 3 8B | Qwen3.5 2B/4B | Fine-tunes only if they pass the schema test |
| 16 GB GPU / 32 GB Mac (dev M4) | Qwen3.5 9B, Ministral 3 14B; gpt-oss-20B after JSON testing (111 tok/s on a 5060 Ti) | Qwen3.5 2B/4B | 35B-A3B (22 GB) fits on the M4 but is tight beside the game and TTS |
| 24 GB GPU / 48-64 GB Mac | Gemma 4 26B-A4B or Qwen3.6 35B-A3B | Qwen3.5 4B or Gemma 4 E4B | Cold 3k prompt in about 1 s on a 3090/4090 |

Sources: model sizes from the [Ollama library](https://ollama.com/library/qwen3.5); speeds from [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6). Tier placement is a synthesis to verify in-game, not a benchmark result.

Public benchmarks do not tell you how these models will play as NPCs. EQ-Bench Creative Writing v3 puts Gemma 4 31B (rubric score 16.01) level with Qwen3.5-397B and well above Mistral Small 3.2 24B (14.31) ([Featherless](https://featherless.ai/blog/best-ai-for-creative-writing-2026), [benchmarklist](https://benchmarklist.com/benchmarks/creative_writing_v3/)). But it rewards long literary prose, while NPC turns need brevity, a consistent voice and obedience to the effect menu. No credible role-play-consistency or refusal-rate benchmark for the small 2026 models turned up.

The decision therefore has to come from a Land-specific test harness: about 50 scripted scenes run through each candidate model, scored on:

- JSON validity and enum correctness;
- staying within the effect menu;
- reply length;
- voice drift over 20 turns;
- refusals.

For agent decisions, a schema like `{choice: enum[option_ids], effects, reason}` makes structural failure impossible even on a 2B model, so only the quality of the choice needs testing. Ollama v0.40.11 also added a "d3" family of decision models (2B-27B) that is worth including ([releases](https://github.com/ollama/ollama/releases)).

On safety, under-refusal is the bigger risk. "Uncensored" role-play fine-tunes remove exactly the guardrail Land's minor-safety line depends on ([Atomic Chat](https://atomic.chat/blog/guides/best-uncensored-llms)). Use stock instruct models, put the rules explicitly in each soul, and filter the `response` string in game code. The `actions` channel needs no filter, because the schema restricts it to a fixed vocabulary.

## Keep MiniLM in ChromaDB, or re-embed into a new collection

Ollama's `/api/embed` takes a batch of inputs and returns `embeddings` ([api.md](https://raw.githubusercontent.com/ollama/ollama/main/docs/api.md)). Chroma ships `OllamaEmbeddingFunction(url=..., model_name=...)` to use it ([Chroma docs](https://docs.trychroma.com/integrations/embedding-models/ollama)).

Land does not need it yet. Chroma's default embedder, all-MiniLM-L6-v2, already runs locally without any cloud service ([Chroma embedding functions](https://docs.trychroma.com/docs/embeddings/embedding-functions)). Keeping it avoids loading a third model into Ollama next to the dialogue and decision models.

If retrieval quality turns out to be the weak point, switching embedders is a migration, not a config change. Chroma stores the embedding function with each collection and raises an "Embedding function conflict" error on a mismatch. Mixing embedders also produces vectors of different dimensions ([fixdevs](https://fixdevs.pages.dev/blog/chromadb-not-working/), [CrewAI community](https://community.crewai.com/t/unable-to-change-model-provider-for-mdxsearchtool/7367)). The safe path:

1. Add a `--embedder ollama:<model>` mode to `chroma_cli.py`.
2. Create `npc_memory__<model>` as a new collection.
3. Re-add every document, reading the old collection through its original embedder.
4. Switch reads over to the new collection.

nomic-embed-text and embeddinggemma are the natural candidates for short NPC memories, but their specifications were not verified in this research.

## Kokoro covers every player tier; Chatterbox adds expressiveness on GPUs

Ollama has no audio output, so TTS needs its own engine. Licensing narrows the field before quality does. These are not usable for a commercial release:

- **XTTS-v2**: non-commercial license, and Coqui has shut down, so no commercial license can be bought;
- **F5-TTS weights**: CC-BY-NC because of the training data;
- **Spark-TTS**: CC BY-NC-SA;
- **Fish Audio S2**: research license;
- **IndexTTS**: bilibili license.

Sources: [Cartesia](https://www.cartesia.ai/learn/open-source-tts), [F5-TTS](https://github.com/SWivid/F5-TTS), [yaps.ai](https://www.yaps.ai/blog/best-local-tts-models). These are clearly commercial-safe: Kokoro-82M (Apache-2.0), Chatterbox (MIT; every output carries an inaudible Perth watermark) and Qwen3-TTS (Apache-2.0 per secondary sources) ([Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI), [Chatterbox](https://github.com/resemble-ai/chatterbox), [Gigazine](https://gigazine.net/gsc_news/en/20260123-qwen3-tts-family-opensource)).

Orpheus is tagged Apache-2.0 but is a Llama-3.2 fine-tune, so it needs legal review ([HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft)). It is also a 3B language model that would compete with the dialogue model for the same GPU, which makes it the worst fit for running beside an LLM.

| Engine | License | Latency evidence | Voice strategy | Tone brackets |
|---|---|---|---|---|
| Kokoro-82M | Apache-2.0 | First audio under 1 s on M3 Pro CPU; about 300 ms on GPU | 54 presets, blendable (`af_bella(2)+af_sky(1)`) | Strip |
| Chatterbox-Turbo | MIT, watermarked | About 470 ms first chunk, ~6 GB VRAM (hardware unstated); 48 s per utterance on CPU | Zero-shot clone from a 7-10 s reference | Map to `[laugh]`, `[cough]` and similar |
| Qwen3-TTS 0.6B/1.7B | Apache-2.0 (secondary sources) | 97 ms first packet (hardware unstated) | 3 s clone; VoiceDesign creates voices from text descriptions | Partial |
| Piper (Rhasspy) | MIT, per-voice licenses | 1.7 s on CPU | Fixed voices | Strip |

Sources: [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI), [Chatterbox](https://github.com/resemble-ai/chatterbox), [Picovoice CPU benchmark](https://picovoice.ai/blog/on-device-tts/), [Emergent Mind](https://api.emergentmind.com/topics/qwen3-tts), [ocdevel](https://ocdevel.com/blog/20250720-tts). Use the Rhasspy MIT build of Piper; the OHF fork is GPLv3.

Kokoro is the default for three reasons. It is the only strong-quality engine with sourced first-audio numbers on both Apple Silicon and modest GPUs. It needs only about 2 GB and can run on the CPU, which leaves the GPU and memory bandwidth to the LLM. And its voices are deterministic, so consistency across sessions comes free.

**For the 20 main NPCs,** blend 2-3 base voices per character (the British `bm_*`/`bf_*` voices suit the setting). Add a per-character speed, such as 0.85 for old men and 1.1 for the excitable teenager, plus an optional `AudioEffectPitchShift` on a per-NPC bus. **For the ~86 generic NPCs,** use 8-12 pool voices with speed and pitch jitter seeded by `npc_id`. Kokoro's weak spots are gruff and child voices.

**For voice cloning,** Qwen3-TTS VoiceDesign can author a timbre from a text description. Render one reference clip per character, then clone it at runtime with Chatterbox. Because no real person's voice is copied, this avoids consent and right-of-publicity problems, which the model licenses do not cover. Chatterbox and Orpheus accept inline paralinguistic tags, so ElevenLabs-style "(sighs)" brackets can be mapped instead of stripped ([Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI)).

**Integration** mirrors the LLM plan. During development, run Kokoro-FastAPI as a sidecar: its OpenAI-style `/v1/audio/speech` streams `pcm` output, which Godot can push into an `AudioStreamGenerator`. That keeps the existing ElevenLabs streaming and `user://` cache code almost unchanged ([Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)). For shipping, avoid bundling Python and PyTorch. Run Kokoro ONNX in-engine, either through NobodyWho's `NobodyWhoTextToSpeech` (which returns WAV bytes; streaming is not documented) or through a custom ONNX Runtime GDExtension ([NobodyWho TTS](https://docs.nobodywho.ooo/godot/text-to-speech)). Keep `DisplayServer.tts_speak` only as an accessibility fallback: OS speech cannot be routed through Godot's audio buses, so it cannot be spatialised or pitch-shifted per NPC ([Godot docs](https://docs.godotengine.org/en/stable/tutorials/audio/text_to_speech.html)).

## The stack to adopt

| Layer | Development (M4, 32 GB) | Shipping to players |
|---|---|---|
| LLM runtime | Ollama v0.40.x, GGUF tags, native `/api/chat` | Bundled `llama-server` sidecar with slot save/restore; NobodyWho if Land moves to Godot 4.6+; Ollama as an optional advanced backend |
| Dialogue model | Qwen3.5 9B as the baseline; Qwen3.5 4B / Gemma 4 E4B for speed; Gemma 4 26B-A4B for a quality ceiling | Chosen by tier from the table above, downloaded on first run (2-5 GB) |
| Agent decisions | Same model, with an enum schema and small `num_predict` | Same model on small tiers; a 2-4B model where memory allows |
| Request settings | `format` schema with `response` first, `think: false`, `num_ctx` 8192 pinned, `keep_alive: -1`, `q8_0` KV cache | The same settings in llama-server terms (`json_schema`, `-ctk q8_0`, `id_slot`) |
| Embeddings | Keep MiniLM in ChromaDB | The same, or a versioned re-embedded collection |
| TTS | Kokoro-FastAPI sidecar | Kokoro ONNX in-engine; Chatterbox-Turbo opt-in on 6 GB+ GPUs |

All of these sit behind backend-agnostic `LLMProvider` and `TTSProvider` interfaces, with Claude and ElevenLabs kept as optional BYOK (bring-your-own-key) backends. The same audio cache, keyed by `(npc_id, text, backend, params)`, serves every TTS backend.

Before committing, run one benchmark nobody has published: on the M4, measure prompt-eval rate, time to first token and decode with Kokoro running alongside a loaded 9B model and a 26B-A4B model. Run `ollama run --verbose` against a real 3.2k-token NPC prompt, both cold and with a cache hit.

## Conclusion

The local stack moves Land's design constraint from tokens per dollar to tokens per second of prompt reading. That puts prompt structure, not model choice, in charge of perceived latency. An NPC architecture with a static prefix, a pinned context window and prewarmed caches will feel responsive on a 9B model. A naively assembled prompt will feel sluggish on any model on a base-M4-class Mac.

The same constraint argues for treating a 4B model as the floor for Mac players. It also explains why the cache controls in `llama-server` and NobodyWho are worth more than Ollama's convenience once the game ships. The most dangerous failure is silent, not slow: a schema-ignoring backend that returns HTTP 200. Strict GDScript validation, plus a CI-style harness that asserts JSON validity across every candidate model and Ollama version, is the one investment that protects every other choice in this stack.
