# Local Ollama models to replace Claude for NPC dialogue and agent decisions in Land (Godot RPG), state as of Nov 2026

Research date: 2026-11-02. These notes come from 15 search and fetch calls. Many quantitative sources are blogs or aggregators, not reproducible `llama-bench` runs. Each source's quality is flagged inline. Anything marked "background knowledge, unverified this session" was not confirmed by a source fetched here, so the report writer should treat it as a lead.

## 1. Which model families are current and strongest (1B-32B, on Ollama) as of late 2026

### Takeaway
The current open families in this size range are Qwen3.5 (Feb/Mar 2026), Qwen3.6 (Apr 2026), Gemma 4 (Apr 2026, now Apache-2.0), Mistral's Ministral 3 line (3B/8B/14B) and gpt-oss-20B. One Oct-2026 source also mentions a Qwen3.8 27B dense model. Three models are the strongest mid-size candidates for a 3k-token system prompt that needs fast decoding: Gemma 4 26B-A4B, Qwen3.5/3.6 35B-A3B (both MoE, with about 3-4B active parameters) and gpt-oss-20B. The dense Gemma 4 31B and Qwen 27B are higher quality but much slower. Llama 3.x, Phi-4 and Mistral NeMo now look like legacy generations next to these.

### Cited Findings
**Qwen3.5**
- The Qwen3.5 family was released around 1 March 2026. The small series (0.8B, 2B, 4B, 9B, plus Base versions) launched on 3 March 2026, and the Qwen team promoted it on Ollama — [Product Hunt](https://www.producthunt.com/p/qwen3/qwen3-5-small); [Emelia review](https://emelia.io/hub/qwen-35-9b-review)
- Ollama `qwen3.5` library tags and download sizes: `0.8b` 1.2-1.3 GB, `2b` 2.7-3.1 GB, `4b` 3.3-4.0 GB, `9b` 6.6-7.6 GB (this is `latest`), `27b` 17-20 GB, `35b` 22 GB, `122b` 81 GB. MLX variants exist for every size up to 35b. All tags list 256K context and text plus image input, and the family carries a "thinking" capability tag. The page describes the architecture as "Gated Delta Networks combined with sparse Mixture-of-Experts" — [Ollama library: qwen3.5](https://ollama.com/library/qwen3.5)
- Ollama issue #14645 refers to the Ollama tag as `qwen3.5:35b-a3b`, which shows the 35B model is a 35B-A3B MoE — [ollama/ollama#14645](https://github.com/ollama/ollama/issues/14645)

**Qwen3.6**
- Qwen3.6-35B-A3B is Apache-2.0. It has 35B total parameters with 3B active, as an MoE of 256 experts (8 routed plus 1 shared active per token). Native context is 262,144 tokens, extensible to about 1M with YaRN. The card says it follows "the February release of the Qwen3.5 series", and its citation is dated April 2026 — [HF model card Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)

**Qwen3.8 27B (single source)**
- A measured hardware roundup dated October 2026 lists "Qwen3.8 27B (dense)" and describes Qwen3.6 27B as "legacy" — [RigBase / dev.to, Oct 24 2026](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6). This is the only source found for Qwen3.8, so it needs confirmation on ollama.com.

**Gemma 4**
- Released 2 April 2026 in four sizes: E2B, E4B, 26B MoE (about 4B active) and 31B Dense. All are Apache 2.0, a change from the Gemma Terms of Use that covered Gemma 3 and earlier — [The Register](https://www.theregister.com/2026/04/02/googles_gemma_4_open_weights/); [DataNorth](https://datanorth.ai/news/google-releases-gemma-4-open-models); [Wikipedia: Gemma](https://en.wikipedia.org/wiki/Gemma_(language_model))
- **Conflict:** RigBase also benchmarks a "Gemma 4 12B" — [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6). That size is not among the four launch sizes, and another article claims "five sizes" — [search summary of Gemma 4 coverage](https://webscraft.org/blog/gemma-4-povniy-oglyad-rozmiri-litsenziya-porivnyannya-z-gemma-3?lang=en). A 12B may have been added after launch, but this is unverified.

**Mistral**
- Mistral Small 4 is a 119B-parameter MoE released 16 March 2026 that combines instruct, reasoning and coding. It is out of range for consumer GPUs — [AlternativeTo](https://alternativeto.net/news/2026/3/mistral-small-4-blends-reasoning-coding-and-multimodal-ai-into-one-open-source-model)
- Ministral 3 comes in 14B, 8B and 3B, all with text and vision input, aimed at edge and local use. Mistral lists Large 3, Small 4 and all three Ministral 3 sizes as Apache 2.0, while Medium 3.5 uses a modified MIT licence — [eWEEK](https://www.eweek.com/news/mistral-3-launch/); [aicomparison.ai](https://aicomparison.ai/mistral-models-guide/)
- Ollama support for Mistral Small 4 was "not ready at launch" according to one undated guide. Current status is unverified — [vucense](https://vucense.com/ai-intelligence/open-source-ai/mistral-small-4-european-sovereign-ai/)

**gpt-oss**
- gpt-oss 20B and 120B are still widely benchmarked in Oct 2026, with gpt-oss-20B in native MXFP4 — [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)

**Role-play community picks**
- Community guides for SillyTavern and Ollama still recommend Mistral NeMo 12B fine-tunes (TheDrummer's Rocinante) for 12 GB GPUs, and Cydonia (also TheDrummer). Stheno 8B and Hermes 3 come up for lighter hardware. These are SEO-style guides with some fabricated model names (for example "Llama 4 Scout (9B)" and "Qwen 3.7 Max"), so treat them as low-quality signal — [Aliteq](https://aliteq.com/best-local-llm-for-creative-writing-roleplay-2026); [aiinsightsnews](https://aiinsightsnews.net/local-llm-for-roleplay/); [serverman](https://www.serverman.co.uk/ai/ollama/best-ollama-models-for-roleplay-chat/)

### Inferences
- For this project the relevant 2026 generation is Qwen3.5/3.6(/3.8), Gemma 4, Ministral 3 and gpt-oss-20B. Llama 3.x (2024), Phi-4 (late 2024 / early 2025), Mistral NeMo (Jul 2024) and DeepSeek-R1 distills (Jan 2025) are a generation or two older. The R1 distills are reasoning-first, which hurts latency and JSON output. The role-play fine-tunes are mostly built on older Mistral NeMo and Mistral Small 3.x bases.
- MoE models with about 3-4B active parameters (Qwen 35B-A3B, Gemma 4 26B-A4B) decode at roughly small-dense-model speed while carrying a larger model's knowledge. That suits NPC dialogue well if the device has memory for 17-22 GB of weights.

### Gaps
- I did not find whether Llama 4 has any small (under 32B) variant on Ollama. Llama 4 Scout and Maverick, from background knowledge, are 109B and 400B MoE, which is too large.
- I did not confirm whether Phi-4 or Phi-4-mini had any 2026 successor.
- I did not confirm whether Qwen3.6 has sizes below 35B-A3B. The HF collection lists 4 items, but the card names none.
- Qwen3.8 rests on one source.
- I did not confirm the current Ollama library tags for Gemma 4, Ministral 3 or gpt-oss.

## 2. Tokens per second and time to first token (prompt processing measured separately)

### Takeaway
Prompt processing (PP) is the binding constraint on the Apple M4 dev machine. On a base M4 (120 GB/s, 10 GPU cores), llama.cpp processes about 221 tokens/s for a 7B Q4_0 prompt. A cold 3,000-token system prompt would therefore take more than 10 s before the first token, far outside the 1 s target. A 1 s first token on Mac is only feasible with KV prefix caching, so that only the new turn's tokens are processed. Discrete NVIDIA GPUs from the 3090 class upward process prompts at about 3,000 tokens/s on 30B-class MoE models, which puts a cold 3k prompt at about 1 s.

### Cited Findings
**Apple Silicon (llama.cpp #4167, LLaMA 7B, Q4_0, build from Nov 2023, so old; newer builds and flash attention are faster)** — [llama.cpp discussion #4167](https://github.com/ggml-org/llama.cpp/discussions/4167)

| Chip | Bandwidth (GB/s) | GPU cores | PP512 (tok/s) | TG128 (tok/s) |
|---|---|---|---|---|
| M4 | 120 | 10 | 221 | 24.1 |
| M4 Pro | 273 | 20 | 440 | 50.7 |
| M4 Max | 546 | 40 | 886 | 83.1 |
| M3 | 100 | 10 | 187 | 21.3 |
| M3 Pro | 150 | 18 | 342 | 30.7 |
| M3 Max | 400 | 40 | 760 | 66.3 |
| M2 | 100 | 10 | 180 | 21.9 |
| M1 | 68 | 8 | 118 | 14.2 |

- **Ollama, base M4 Mac mini 16 GB:** Qwen2.5 7B Q4_K_M showed a prompt eval rate of about 108 tok/s on a 56-token prompt. Short prompts understate throughput — [r/LocalLLaMA mirror](https://reddit.zackpollard.pro/r/LocalLLaMA/s/eLctTR09XZ)
- **gpt-oss-20B decode, llama.cpp:** M4 Max (36 GB) 92.4 tok/s; M1 Max 75.2; M3 Ultra 115.5 — [RigBase, citing llama.cpp #15396 / #4167](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)
- **Newer Apple data:** Qwen3.6 35B-A3B at 4-bit MLX on an M5 Max (36 GB) reaches 145.8 tok/s decode, and Qwen3.8 27B at 4-bit MLX on an M5 Max (128 GB) reaches 31 tok/s — [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)

**NVIDIA decode (tg128, mostly the llamabench.ai community aggregate)** — [RigBase, Oct 2026](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)

| Model | RTX 4090 | RTX 5090 | Other |
|---|---|---|---|
| Gemma 4 26B-A4B | 164 | 235 | — |
| Gemma 4 31B dense | 43.8 | 70.0 | — |
| Gemma 4 12B (see size conflict in §1) | 98.1 | 142 | 5070 Ti 87.6; 3060 12 GB 38.5 |
| gpt-oss 20B | 203 | 313 | 3090 161.8; 5060 Ti 16 GB 111.5; 3060 system run 84.0 (Geerling) |
| Qwen3.6 35B-A3B | 160.6 (Q4_K_M) | 258 | 3090 146-153; 3090 at about 90K context 139.6 |
| Qwen3.8 27B dense | — | 75.2 (Q4_K_M) | 3090 40.4; 5060 Ti 16 GB 28.0 (IQ4_XS, 8K); 3060 12 GB 5.2-6.7 (does not fit, offloads) |

- **Multi-token prediction (MTP) on Qwen3.8 27B, RTX 3090, llama.cpp:** decode rose from 40.4 to 72.5 tok/s on a code prompt and reached 50.9 on a reasoning prompt — [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)
- **Other Qwen3 30B-A3B decode figures on a 4090:** about 145 tok/s at Q4_K_M — [canitrun.dev](https://canitrun.dev/gpus/rtx-4090/); 120-196 tok/s depending on quant, context and backend — [dev.to guide](https://dev.to/jovan_chan_9500711396d4e6/qwen3-30b-a3b-local-ai-guide-196-toks-on-one-rtx-4090-and-what-moe-means-for-your-gpu-33ng)
- **RTX 3090 prompt processing at 4k context:** Qwen3 30B-A3B about 3,000 tok/s and Gemma 4 26B about 3,600 tok/s; Gemma 4 26B decode about 119 tok/s — [hardware-corner](https://www.hardware-corner.net/gpu-llm-benchmarks/rtx-3090/)
- **RTX 3060 12 GB:** Qwen3 30B-A3B at Q4 does not fit in VRAM and needs offloading — [dev.to guide](https://dev.to/jovan_chan_9500711396d4e6/qwen3-30b-a3b-local-ai-guide-196-toks-on-one-rtx-4090-and-what-moe-means-for-your-gpu-33ng)

### Inferences
These are my arithmetic, not measured.
- **Base M4, cold 3,000-token prompt:** about 13.6 s for a 7-9B model at the 2023-build rate of 221 tok/s. Even with a 2x newer-build gain it would be about 6-7 s. A 2-4B model would be roughly 3-5 s, and a MoE with 3-4B active would be about 4-7 s. The first-token target is therefore unreachable on cold prompts. It requires:
  - static-first prompt layout (soul, world rules and effect menu first; memories and the turn last);
  - keeping the model loaded (`keep_alive`);
  - reusing the KV prefix.

  Ollama/llama.cpp reuse a matching prompt prefix within a slot. Switching between NPCs with different souls breaks the prefix, unless shared world rules come first and each NPC's soul comes second. Prewarming the prefix when the player approaches an NPC hides the remaining cost.
- **Base M4 decode, 9B dense:** about 18-22 tok/s, extrapolated from 24 tok/s for 7B. A full reply plus JSON of about 120-180 tokens takes about 6-9 s, which misses the 2-4 s target. A 3-4B-active MoE should decode at roughly 2x that rate (bandwidth scales with active parameters), so about 3-5 s. But its 17-22 GB of weights leave only about 10 GB of the 32 GB for macOS, the game and TTS, which is tight.
- **M4 Pro / Max:** PP is 2x and 4x the base M4, which makes 9B-class or MoE dialogue workable with caching.
- **24 GB GPUs (3090/4090):** Gemma 4 26B-A4B or Qwen3.6 35B-A3B at Q4 gives about 1 s for a cold 3k prompt and 140-165 tok/s decode, comfortably inside target. The catch is that 17-22 GB of weights leaves little VRAM for the game and TTS.
- **12-16 GB GPUs:** Gemma 4 E4B / 12B, Qwen3.5 9B, Ministral 3 8B/14B or gpt-oss-20B (about 13 GB in MXFP4, background knowledge) fit.
- **8 GB GPUs:** 4B-class models (Qwen3.5 4B, Gemma 4 E4B, Ministral 3 3B).
- Keep JSON compact (short keys, few fields), because the `analysis` object's tokens cost as much as the spoken line's.

### Gaps
- I found no M4 (base) llama-bench PP numbers for 2026 builds or for the specific 2026 models, and no measured time to first token at an 8k-token prompt. RigBase reportedly added these on its live site, but they were not in the article text.
- No RTX 3060, 4070 or 4090 PP512 numbers for the 2026 models.
- The RigBase figures mix engines and builds, and some contradict each other within the page (gpt-oss-20B on a 4090 is 203 in one table and 279.65 in another).

## 3. Structured JSON reliability (Ollama `format` schema versus unconstrained)

### Takeaway
Ollama's `format` with a full JSON Schema constrains generation token by token, so it is the right default. But for most of 2026 a bug silently dropped the constraint on Qwen3.5/3.6 (and Qwen3 on 0.30.x) when thinking was disabled, which is exactly the mode NPC dialogue needs. The fix landed in Ollama 0.31.2 (July 2026). Require at least 0.31.2, use non-thinking mode, still validate and retry in Godot, and avoid gpt-oss for strict schemas unless it has been tested.

### Cited Findings
- **Issue #14645**, "format is ignored when think is disabled for qwen3.5 series", opened 5 March 2026 against qwen3.5:35b-a3b on Ollama 0.17.6.
  - **Cause:** Ollama waits for an end-of-thinking token before applying the grammar mask. The Qwen template injects an empty `<think></think>` when thinking is off, so the mask never engages and the model returns free text.
  - **Still broken in:** 0.18.2 through 0.21.0, and still reported on the chat path in 0.30.7. One user said Qwen3 was affected from 0.30.0.
  - **Fixes:** a Gemma 4 variant was fixed in 0.21.1 (PR #15678). The issue was closed via PR #15901, and the reporter confirmed the fix in 0.31.2 on 9 July 2026.
  - **Workarounds:** use `/api/generate` instead of `/api/chat`, or create a custom model without the thinking capability flag.

  — [ollama/ollama#14645](https://github.com/ollama/ollama/issues/14645)
- **Schema versus plain JSON:** `format: "json"` is loose. The model "will probably respond with JSON but might not follow the instructed schema", so a full schema should be passed. Property `description`s are "silently ignored" by Ollama's schema enforcement, so semantics must go in the prompt. `format` alone is unreliable on smaller models — [makandracards](https://makandracards.com/makandra/626409-ollama-structured-input-output)
- **gpt-oss on Ollama** has structured-output problems: reasoning traces appear when not requested, which breaks schema parsing. The same author contrasts this with Qwen3, where "structured output works so well with Ollama" — [Glukhov, Oct 2025](https://www.glukhov.org/post/2025/10/ollama-gpt-oss-structured-output-issues/) (older data)
- **Disabling thinking on Qwen3.6:** it does not support Qwen3's `/think` / `/nothink` soft switch. Thinking is on by default and is disabled via `enable_thinking: False` in the chat template kwargs. Recommended non-thinking sampling: temperature 0.7, top_p 0.8, top_k 20, presence_penalty 1.5 — [HF Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)

### Inferences
- **Thinking mode:** for NPC turns, thinking adds hundreds of hidden tokens, which destroys the 2-4 s budget, and was the trigger for the format bug. Use `think: false` on Ollama ≥ 0.31.2 and smoke-test that a schema violation is impossible, for example by asserting enum values over 100 calls.
- **Truncation:** set `num_predict` high enough for the whole object, because a hard cutoff mid-object yields invalid JSON even under a grammar. Keep `response` length bounded in the prompt and with `maxLength` in the schema. Whether Ollama honours `maxLength` is unverified.
- **Enums:** enum fields and small integer ranges are well suited to grammar constraints. Validate deltas in game code anyway (clamp).
- **Small models:** for the 1-4B agent-decision model, a schema like `{choice: enum[...], effects: [...], reason: string}` with the option IDs as an enum makes structural failure impossible. Decision quality is the remaining risk.

### Gaps
- I found no quantitative schema-adherence or JSON-validity benchmark comparing these specific 2026 models under Ollama.
- I did not verify whether Ollama now enforces `minimum`/`maximum`/`maxLength`.
- No BFCL (function-calling leaderboard) scores retrieved for Gemma 4, Qwen3.5/3.6 or Ministral 3.

## 4. Character quality and credible role-play benchmarks

### Takeaway
EQ-Bench Creative Writing v3 is the most-cited open writing benchmark. Its rubric scores (judged by an LLM) and Elo place Gemma 4 31B at about 16.0, level with Qwen3.5-397B-A17B, far above Mistral Small 3.2 24B at about 14.3. Most numbers here come from mirrors that disagree on Elo. No reliable source was found for role-play-specific consistency of the small 2026 models.

### Cited Findings
- **EQ-Bench Creative Writing v3 scores:**
  - Gemma 4 31B: rubric 16.01, Elo 1407.6, level with Qwen3.5-397B-A17B at 16.00 — [Featherless](https://featherless.ai/blog/best-ai-for-creative-writing-2026). Another tracker lists Gemma 4 31B at Elo 1369, rank 75 — [llmlearner / tracker](https://llmlearner.com/rankings/creative-writing). That is an Elo conflict.
  - Qwen3.5-397B-A17B: Elo 1486.1, score 16 — [benchmarklist](https://benchmarklist.com/benchmarks/creative_writing_v3/)
  - Mistral-Small-3.2-24B-Instruct-2506: 14.31 / Elo 1242.2. Older Mistral Small 24B releases score around 8 — [benchmarklist](https://benchmarklist.com/benchmarks/creative_writing_v3/)
- **EQ-Bench methodology:** "Slop" counts LLM-typical words and phrases against a list, and "Repetition" sums the frequencies of top words, bigrams and trigrams. Both matter for NPC voice. The live table loads dynamically and could not be scraped — [eqbench.com creative writing](https://eqbench.com/creative_writing.html); an Open Writing Leaderboard also exists — [owl.eqbench.com](https://owl.eqbench.com/)
- **Community view:** NeMo-based fine-tunes such as Rocinante are favoured for 12 GB role-play, and Cydonia for larger cards — [Aliteq](https://aliteq.com/best-local-llm-for-creative-writing-roleplay-2026). Low-quality sources.

### Inferences
- Creative-writing scores reward long literary prose. NPC turns need the opposite: brevity, voice consistency and obeying the effect menu. Weight instruction following (IFEval-style) and a custom in-game evaluation above creative-writing Elo.
- RP fine-tunes improve voice and reduce refusals, but they usually inherit older bases (NeMo 12B / Mistral Small 3.x). They tend to have weaker instruction following on long, rule-heavy system prompts and to be wordier, which runs against a 3k-token rule prompt and strict JSON. Use them for dialogue only after a schema-adherence test.
- The best evaluation is a project-specific harness: 50 scripted scenes × candidate models, scoring JSON validity, enum correctness, staying within the effect menu, reply length, voice drift over 20 turns, and refusals.

### Gaps
- I could not retrieve current EQ-Bench, IFEval, LMArena or Artificial Analysis numbers for the small and mid 2026 models (Gemma 4 26B-A4B / E4B, Qwen3.5 9B/4B, Qwen3.6 35B-A3B, Ministral 3, gpt-oss-20B).
- No credible role-play-specific leaderboard data was found (character-consistency evaluations).
- No 2026 measurements were found for Cydonia, Rocinante or Magnum.

## 5. Refusals: dark fiction versus the minor-safety line

### Takeaway
No credible, quantified 2026 refusal benchmark for these specific models was found. The only finding is that community guides steer role-players toward "uncensored" fine-tunes and that ordinary instruct models need persona framing. The game should not rely on model behaviour for the minor-safety line.

### Cited Findings
- Guides dedicated to "uncensored" local LLMs exist because stock instruct models refuse some fiction; fine-tunes are the community remedy — [Atomic Chat](https://atomic.chat/blog/guides/best-uncensored-llms); [aiinsightsnews](https://aiinsightsnews.net/local-llm-for-roleplay/) (low-quality sources)

### Inferences
- Under-refusal is the real risk with RP fine-tunes and "abliterated" models: they remove the guardrail that the minor-safety requirement depends on. Over-refusal is the risk with gpt-oss and possibly Phi (background knowledge: both are tuned conservatively; unverified this session).
- Recommended architecture:
  - Use stock instruct models (Gemma 4, Qwen3.5/3.6, Ministral 3), which typically accept non-graphic villainy when framed as fiction in the system prompt.
  - Put explicit rules in the soul ("never sexual content; children are protected and treated with care").
  - Add a hard output filter in game code. Optionally run a small classifier pass with the same small model, or a dedicated safety model such as the "Shieldstral" Mistral lists as Apache 2.0 — [aicomparison.ai](https://aicomparison.ai/mistral-models-guide/); its capabilities are unverified.
- Because the JSON `actions` come from a fixed vocabulary, the effect channel cannot express disallowed acts. Only the `response` string needs filtering.

### Gaps
- No refusal-rate data (for example from benchmarks such as XSTest or SORRY-Bench) was found for Gemma 4, Qwen3.5/3.6, Ministral 3 or gpt-oss.
- No evidence was gathered on whether RP fine-tunes keep the minor-safety refusals.

## 6. Licences for commercial distribution (game that bundles or downloads weights)

### Takeaway
Gemma 4, Qwen3.6 (and likely Qwen3.5), Ministral 3, Mistral Small 4 and gpt-oss are all permissive (Apache-2.0), which allows bundling in a commercial game with notice. Gemma 4's switch to Apache-2.0 removes the main obstacle of Gemma 3's terms. Llama and the role-play fine-tunes need per-model licence checks.

### Cited Findings
- Gemma 4: Apache 2.0 at every size. Gemma 3 and earlier were under the source-available Gemma Terms of Use — [The Register](https://www.theregister.com/2026/04/02/googles_gemma_4_open_weights/); [Wikipedia](https://en.wikipedia.org/wiki/Gemma_(language_model))
- Qwen3.6-35B-A3B: Apache-2.0 — [HF model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- Ollama's qwen3.5 page says "open-source" but names no licence — [Ollama library](https://ollama.com/library/qwen3.5)
- Mistral: Large 3, Small 4 and Ministral 3 (3B/8B/14B) are Apache 2.0; Medium 3.5 uses a modified MIT licence — [aicomparison.ai](https://aicomparison.ai/mistral-models-guide/); [eWEEK](https://www.eweek.com/news/mistral-3-launch/)

### Inferences
Unverified this session; these come from background knowledge.
- gpt-oss-20B is Apache-2.0 plus a usage policy.
- Phi-4 and Phi-4-mini are MIT.
- Mistral NeMo 12B and Mistral Small 3.x are Apache-2.0, so Rocinante (NeMo base) and Cydonia (Mistral Small base) inherit Apache-2.0 base terms. Fine-tuners sometimes add their own terms, so check each Hugging Face card.
- Magnum variants span bases (Qwen2.5-72B used the restrictive Qwen licence, and others used Llama), so their terms vary by version.
- The Llama 3.x community licence allows commercial use but requires "Built with Llama" attribution and acceptance of the Acceptable Use Policy, and adds a separate licence requirement above 700M monthly active users. Llama 4's licence restricted EU-domiciled entities from its multimodal models.
- Apache-2.0 obligations are to ship the LICENSE and NOTICE and to state modifications. Ollama's own runtime is MIT.

### Gaps
- I did not confirm the Qwen3.5 small-model licence (expected Apache-2.0).
- I did not confirm the Llama 3.x / 4 licence text, the Phi-4 licence, or the gpt-oss licence from primary pages in this session.

## 7. Small models for cheap tasks, plus speculative decoding and draft models in Ollama

### Takeaway
A split architecture is viable. A 1-4B model (Qwen3.5 2B/4B, Gemma 4 E2B/E4B, Ministral 3 3B) handles agent decisions and intent classification under a strict enum schema, while a mid-size or MoE model handles dialogue. Speculative decoding is mature in llama.cpp, LM Studio and vLLM. In Ollama, only MTP-style support is reported, by an unverified secondary source. Rely on MTP-capable models and prefix caching rather than draft models in Ollama.

### Cited Findings
- **Draft models elsewhere:** llama.cpp's server supports draft-model speculative decoding and draftless n-gram methods — [llama.cpp speculative docs mirror](https://huggingface.co/OpenTransformer/llama.cpp-prismml/blob/main/docs/speculative.md). LM Studio exposes a main plus draft model in its llama.cpp and MLX engines — [LM Studio 0.3.10](https://lmstudio.ai/blog/lmstudio-v0.3.10)
- **Ollama:** a secondary tutorial claims Ollama shipped native MTP-based speculative decoding in v0.32.6. No official Ollama documentation for draft-model speculation was found — [tech-insider](https://tech-insider.org/speculative-decoding-setup-2026/) (unverified)
- **MTP gains:** Qwen3.8 27B on an RTX 3090 rose from 40.4 to 72.5 tok/s with MTP; on Strix Halo, from 9.59 to 18.01; on DGX Spark (vLLM), from 11.0 to 19.0. Qwen3.6 35B-A3B on 2× 3090 under vLLM rose from 149 to 225-231 tok/s with MTP-3 — [RigBase](https://dev.to/rigbase/what-gpu-do-you-need-for-qwen38-qwen36-gemma-4-and-gpt-oss-locally-measured-oct-2026-1eg6)
- **Small sizes on Ollama:** qwen3.5 0.8b (1.2 GB), 2b (2.7-3.1 GB), 4b (3.3-4.0 GB) — [Ollama library](https://ollama.com/library/qwen3.5)
- **Gemma 4 E2B/E4B:** reportedly about 2 GB and 3.6 GB at 4-bit (unverified) — [search summary, Gemma 4 guides](https://gemma4all.com/blog/gemma-4-download)

### Inferences
- **Decisions:** an agent decision with 2-4 options needs very few output tokens. With prefix caching, a 2-4B model should answer in well under 1 s even on a base M4. The quality risk is reasoning about effects, so keep `reason` short and put option-relevant facts at the end of the prompt.
- **Memory cost of two models:** loading two models doubles resident memory. On 8-16 GB devices, using one model (for example a 4B or 9B) for both tasks may beat a split. Ollama can keep several models loaded (`OLLAMA_MAX_LOADED_MODELS`) at the cost of memory.
- **Draft models:** speculative decoding with a draft model helps decode speed (typically about 1.5-2x on predictable text) but does nothing for prompt processing, which is the Mac bottleneck. Using llama.cpp server directly instead of Ollama would unlock draft models, n-gram speculation and finer slot / KV-cache control (`--cache-reuse`, saving and restoring slots per NPC). That may matter more for Land than model choice.

### Gaps
- I did not confirm Ollama's current speculative-decoding status from official release notes.
- No measured intent-classification or decision accuracy was found for 1-4B models.

---

### Provisional shortlist per hardware tier (synthesised from the above; verify with an in-game evaluation)

All tiers assume:
- non-thinking mode;
- Ollama ≥ 0.31.2 with a full-schema `format`;
- static-first prompt layout plus KV prefix reuse;
- memory left free for the game and TTS.

**8 GB GPU / 16 GB Mac**
- Dialogue: Qwen3.5 4B, Gemma 4 E4B or Ministral 3 3B.
- Decisions: the same model, or Qwen3.5 0.8B/2B or Gemma 4 E2B.

**12 GB GPU / 24 GB Mac**
- Dialogue: Qwen3.5 9B (6.6-7.6 GB), Ministral 3 8B or Gemma 4 E4B.
- Gemma 4 12B, if that size exists (38.5 tok/s decode on a 3060).
- A NeMo-based RP fine-tune (Rocinante) only if it passes the schema test.
- Decisions: Qwen3.5 2B/4B.

**16 GB GPU / 32 GB Mac (the M4 dev machine)**
- Dialogue: gpt-oss-20B (111 tok/s on a 5060 Ti; test its JSON and refusals first), Ministral 3 14B or Qwen3.5 9B.
- On the 32 GB M4, Qwen3.5/3.6 35B-A3B (22 GB) or Gemma 4 26B-A4B is possible but tight. A cold-prompt first token is several seconds, so caching is mandatory.
- Decisions: Qwen3.5 2B/4B.

**24 GB GPU / 48-64 GB Mac**
- Dialogue: Gemma 4 26B-A4B (164 tok/s on a 4090; about 3,600 tok/s PP on a 3090) or Qwen3.6 35B-A3B (160 tok/s on a 4090).
- Gemma 4 31B or Qwen3.8 27B dense for quality, but only about 40-44 tok/s.
- Decisions: Qwen3.5 4B or Gemma 4 E4B.
