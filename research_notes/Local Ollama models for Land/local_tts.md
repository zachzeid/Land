# Local / offline TTS to replace ElevenLabs in a Godot 4.5 RPG (state as of Nov 2026)

Scope note: about 16 searches and fetches. Primary sources (GitHub READMEs, HF model cards, Godot docs) were used where fetched. Several 2026 roundup blogs are secondary, and their figures often state no hardware. Each such figure is labelled. No Apple-Silicon RTF numbers for Chatterbox or Orpheus turned up from a source that states its hardware, so those still need benchmarking on the developer's M4.

## 1. Candidate landscape and licensing for commercial game distribution

### Takeaway
Engines whose code and weights are both clearly commercial-safe: Kokoro-82M (Apache-2.0), Chatterbox / Chatterbox-Turbo / Nano / Multilingual (MIT, with a mandatory watermark), Qwen3-TTS (Apache-2.0 per multiple sources), Kitten TTS (Apache-2.0), Dia, Zonos and Sesame CSM (Apache-2.0 per secondary sources), and the original Rhasspy Piper (MIT; each voice has its own licence). These are not usable for a commercial release without a paid licence: XTTS-v2 (CPML non-commercial, and Coqui is defunct), F5-TTS weights (CC-BY-NC), Spark-TTS (CC BY-NC-SA), Fish Audio S2 / OpenAudio (research licence; commercial use needs a paid licence), and IndexTTS (bilibili licence). Orpheus is tagged Apache-2.0 but is a Llama-3.2 finetune, so its licence needs legal review.

### Cited Findings
**Permissive / commercial-OK**
- Kokoro-82M: Apache-2.0 for both weights and the Kokoro-FastAPI wrapper. The StyleTTS2-derived inference code is MIT. — [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- Kokoro: 82M params, 54 preset voices, no voice cloning, 8 languages, 2-3 GB VRAM, runs on CPU. — [ocdevel roundup (dated Jul 2025, rankings labelled June 2026)](https://ocdevel.com/blog/20250720-tts)
- Chatterbox: MIT licence. Variants are Turbo (350M, English, low latency), Nano (110M, English, CPU/on-device, reportedly 3x realtime on 8 CPU cores), Multilingual V3 (0.5B, 23+ languages), the original (500M, English, with "exaggeration"/CFG emotion controls), and six 500M single-language packs. — [resemble-ai/chatterbox](https://github.com/resemble-ai/chatterbox)
- Chatterbox embeds Resemble's Perth watermark, "imperceptible" and durable through MP3, in every output. — [resemble-ai/chatterbox](https://github.com/resemble-ai/chatterbox)
- Orpheus 3B (canopylabs/orpheus-3b-0.1-ft): the HF card tags it apache-2.0. It is finetuned from meta-llama/Llama-3.2-3B-Instruct, the repo is gated, and it is English only. Metadata shows "4B params, F32" despite the 3B name. — [HF model card](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft)
- Orpheus-FastAPI (the llama.cpp/LM Studio front end) is Apache-2.0. — [Lex-au/Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI)
- Qwen3-TTS (0.6B and 1.7B, including a 1.7B "VoiceDesign" model) is Apache-2.0 according to several secondary sources. One aggregator said the README did not state the licence. — [Gigazine](https://gigazine.net/gsc_news/en/20260123-qwen3-tts-family-opensource); [SourcePulse](https://www.sourcepulse.org/projects/23133865)
- Dia (Nari Labs), Zonos (Zyphra) and Sesame CSM are listed as Apache-2.0, commercial OK. Zonos speaks English, Japanese, Chinese, French and German. — [Cartesia licence comparison](https://www.cartesia.ai/learn/open-source-tts); [yaps.ai licence-checked list](https://www.yaps.ai/blog/best-local-tts-models)
- Kitten TTS Nano: Apache-2.0. Soprano TTS and Supertonic TTS 2: MIT. Pocket TTS: the page says MIT in one place and Apache-2.0 in another. — [Picovoice benchmark (Jul/Aug 2026)](https://picovoice.ai/blog/on-device-tts/)
- Supertonic-2 (66M) is listed as OpenRAIL-M, which carries use restrictions rather than being a plain permissive licence. — [spokes-wiki open-weight TTS](https://spokes-wiki.pages.dev/speech-audio-wiki/open-weight-tts)
- Piper: the original Rhasspy project is MIT. The OHF "v1" fork is GPLv3, which requires releasing derivative source under the GPL and may conflict with app-store terms if linked into a proprietary app. — [Picovoice](https://picovoice.ai/blog/on-device-tts/)
- CosyVoice 3.0 (0.5B): Apache-2.0, zero-shot cloning, about 150 ms streaming (hardware unstated). — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Audio8-TTS (~170M) uses a community licence that is free below US$2M annual revenue. — [spokes-wiki](https://spokes-wiki.pages.dev/speech-audio-wiki/open-weight-tts)

**Restricted / non-commercial**
- XTTS-v2: the Coqui Public Model License is non-commercial. Coqui has shut down, so no commercial licence can be bought. — [Cartesia](https://www.cartesia.ai/learn/open-source-tts); [yaps.ai](https://www.yaps.ai/blog/best-local-tts-models). Note: spokes-wiki wrongly groups XTTS as "permissive" ([link](https://spokes-wiki.pages.dev/speech-audio-wiki/open-weight-tts)). Treat that as an error.
- F5-TTS: code is MIT, but the pretrained models are CC-BY-NC "due to the training data Emilia". — [SWivid/F5-TTS](https://github.com/SWivid/F5-TTS). The ocdevel roundup lists F5 as "MIT", which conflates code with weights ([link](https://ocdevel.com/blog/20250720-tts)).
- Spark-TTS: CC BY-NC-SA 4.0, personal and non-commercial use only. One source says it moved there from Apache-2.0. — [Cartesia](https://www.cartesia.ai/learn/open-source-tts); [yaps.ai](https://www.yaps.ai/blog/best-local-tts-models)
- Fish Audio S2 / S2 Pro (4-5B): research licence, commercial use needs a paid licence. — [ocdevel](https://ocdevel.com/blog/20250720-tts); [spokes-wiki](https://spokes-wiki.pages.dev/speech-audio-wiki/open-weight-tts)
- Higgs Audio (Boson AI): sources conflict. V2 is listed as Apache-2.0 in one source, while another says the newer V3 weights are research / non-commercial. Check the specific checkpoint. — [Cartesia](https://www.cartesia.ai/learn/open-source-tts); [yaps.ai](https://www.yaps.ai/blog/best-local-tts-models)
- IndexTTS / IndexTTS-2.5: bilibili licence; contact bilibili for commercial use. — [yaps.ai](https://www.yaps.ai/blog/best-local-tts-models)
- VibeVoice (Microsoft, 1.5B): "MIT (research only)", built for long-form multi-speaker podcasts rather than cloning. — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Picovoice Orca (8 MB, 106 ms FTTS on CPU) is commercial-licence only. It is a paid alternative, not open. — [Picovoice](https://picovoice.ai/blog/on-device-tts/)

### Inferences
- Orpheus: the Apache-2.0 tag on a Llama-3.2 finetune most likely does not remove the obligations of the Llama 3.2 Community License, such as attribution ("Built with Llama"), the acceptable-use policy and the 700M-MAU clause. For a small indie game these are probably satisfiable, but get legal review before shipping the weights inside a game.
- Chatterbox's watermark is harmless for a game, and arguably good practice for cloned voices. It does mean every shipped line is detectable as AI-generated, so disclose it in the credits or store page.
- "MIT (research only)" (VibeVoice) and OpenRAIL-M (Supertonic) are not plain permissive licences. Exclude them unless the licence text is reviewed.
- Piper voices: each `.onnx` voice inherits its training dataset's licence. Some voices are CC-BY or public domain, and some are research or non-commercial. Check each voice's MODEL_CARD before shipping (piper-voices model cards were not fetched here; see Gaps).

### Gaps
- Licence texts were not fetched directly for Dia, Zonos, Sesame CSM, Higgs V2/V3, IndexTTS2, Kyutai TTS, MeloTTS (believed MIT), OpenVoice V2 (believed MIT since 2024), Parler-TTS (believed Apache-2.0) or StyleTTS2 (believed MIT code). Those "believed" values come from prior knowledge, unverified in this session, and need confirmation from the repos.
- The SNAC codec's licence (needed for Orpheus) was not verified.
- The per-voice licence table for rhasspy/piper-voices was not fetched.
- VibeVoice's repo history was not verified (prior knowledge suggests Microsoft pulled its code in 2025).

## 2. Latency, RTF, streaming and hardware (CPU, Apple Silicon, NVIDIA)

### Takeaway
Kokoro is the only strong-quality engine with numbers that clearly meet a 300-800 ms first-audio target on both Apple Silicon and modest GPUs. The figures: under 1 s first audio on an M3 Pro CPU in Kokoro-FastAPI streaming, and about 300 ms on GPU. Chatterbox-Turbo and Qwen3-TTS-0.6B claim roughly 100-500 ms on GPU, but those claims come with no hardware stated. Their CPU performance is poor (Chatterbox-Turbo took about 48 s per utterance on a Ryzen CPU). Orpheus is bandwidth-bound as a 3B LLM, gets about 2x realtime only on high-end GPUs, and would compete directly with the game's 4-14B LLM.

### Cited Findings
- Kokoro-FastAPI streaming, first-token latency: about 300 ms on GPU (chunk 400); about 3,500 ms on an old i7 CPU; under 1 s on an Apple M3 Pro CPU (chunk 200). Realtime speed is about 35-100x on an RTX 4060 Ti 16 GB. MPS is supported when run natively via `uv`; the Docker GPU image is CUDA-only. — [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- Kokoro speed: about 200x realtime on an RTX 4090, 36x on a T4 and 5x on a 32-core CPU. — [ocdevel](https://ocdevel.com/blog/20250720-tts). RTF 0.03 on an RTX 3090. — [GigaGPU](https://gigagpu.com/tts-latency-benchmarks/)
- Picovoice CPU benchmark (Ryzen 7 5700X, 64 GB, about 200 voice-assistant turns; published Jul 2026, updated Aug 2026). FTTS means first token to speech; the core-hour ratio is below 1 when faster than realtime on one core.

  | Engine | FTTS | Core-hour ratio | Peak memory | Model size | Streaming |
  |---|---|---|---|---|---|
  | Piper | 1,720 ms | 0.35x | 2.6 GB | 61 MB | out |
  | Pocket TTS | 1,713 ms | 0.37x | 610 MB | 242 MB | out |
  | Supertonic 2 | 2,612 ms | 0.52x | 450 MB | 262 MB | out |
  | Kokoro | 3,658 ms | 1.28x | 2.0 GB | 341 MB | out |
  | Kitten Nano | 10,483 ms | 3.1x | 320 MB | 42 MB | none |
  | Chatterbox-Turbo | 48,281 ms | 13.4x | 7.5 GB | 2,980 MB | none |

  Source: [Picovoice](https://picovoice.ai/blog/on-device-tts/). The test runs on CPU only, its FTTS includes their pipeline's chunking, and Picovoice is a vendor whose own product wins the benchmark.
- Chatterbox-Turbo: about 2x realtime and about 470 ms first chunk, ~6 GB VRAM, hardware unstated. Multilingual uses 8-16 GB VRAM. — [ocdevel](https://ocdevel.com/blog/20250720-tts). The official README does not mention streaming. — [chatterbox](https://github.com/resemble-ai/chatterbox)
- Chatterbox runs on Apple Silicon: the README shows `"mps"` as a device option and ships `example_for_mac.py`. — [chatterbox](https://github.com/resemble-ai/chatterbox)
- Qwen3-TTS: the 12Hz-0.6B model has a 97 ms first packet and RTF about 0.29; the 25Hz-1.7B model has a 150 ms first packet. Hardware unstated. — [Emergent Mind summary](https://api.emergentmind.com/topics/qwen3-tts). VRAM is 4-8 GB. — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- F5-TTS on one NVIDIA L20 at 16 NFE: client-server 253 ms average latency, RTF 0.039; offline PyTorch RTF 0.147. Streaming is not explicitly claimed. Apple Silicon works through PyTorch, plus a third-party MLX port (f5-tts-mlx). — [F5-TTS](https://github.com/SWivid/F5-TTS)
- Orpheus: the model card claims about 200 ms streaming latency, or about 100 ms with input streaming. — [HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft). Orpheus-FastAPI reports about 2x realtime on high-end GPUs. It is optimised for an RTX 4090, recommends 16 GB+ VRAM and has a CPU fallback. Q2_K runs about 50% faster than Q8_0. Apple Silicon is not mentioned, and the `/v1/audio/speech` endpoint outputs WAV only, with no documented streaming. — [Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI)
- Orpheus architecture: a Llama-3B GGUF backbone plus a separate SNAC 24 kHz decoder. — [rlx-orpheus crate](https://docs.rs/crate/rlx-orpheus/latest/source/src/lib.rs). Community reports say SNAC segfaults on AMD ROCm (CPU works but is slow), and the base model is English only. — [r/LocalLLaMA, Mar 2025](https://redlib.hbubli.cc/r/LocalLLaMA/comments/1jgopeg/orpheusfastapi_local_tts_with_8_voices_emotion)
- One roundup argues that autoregressive speech LLMs such as Orpheus are memory-bandwidth limited. — [localaimaster](https://localaimaster.com/blog/best-local-tts-models)
- Fish Audio S2: RTF 0.195 on a datacenter GPU, 12-24 GB VRAM. — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Godot's built-in OS TTS has variable latency by OS. On Android and Web it may depend on network services. — [Godot docs](https://docs.godotengine.org/en/stable/tutorials/audio/text_to_speech.html)

### Inferences
- On an M4 with 32 GB of unified memory running an 8-14B LLM, Kokoro costs about 0.3-2 GB and can run on CPU, which leaves the GPU and memory bandwidth to the LLM. That makes it the safest default. Chatterbox-Turbo (about 3 GB of weights, 6 GB working) and Qwen3-TTS-0.6B can probably fit, but they contend with the LLM for GPU time. Orpheus 3B would roughly double LLM-style token generation load, because it generates about 7 SNAC frames' worth of tokens per audio frame. It is the worst fit for "TTS alongside an LLM".
- With 1-4-sentence lines and a sentence-level pipeline (LLM emits sentence 1, then TTS runs, then playback while sentence 2 generates), non-streaming engines are acceptable when synthesis of one short sentence takes under about 500 ms. In-model streaming matters less than raw per-sentence speed.
- CPU-only player machines: only Piper, Pocket TTS, Supertonic, Kokoro and Chatterbox-Nano are viable. Even those show 1.7-3.7 s FTTS in Picovoice's pipeline, so pre-generation and caching of scripted lines matters.

### Gaps
- No source states its hardware for M4 or M-series RTF for Chatterbox, Qwen3-TTS, Orpheus GGUF or Zonos. The developer needs a local benchmark.
- No first-party time-to-first-audio for Dia, Zonos, CSM or Higgs was found in this session.
- Chatterbox-Turbo's 470 ms figure has no hardware attribution.

## 3. Voice quality, expressiveness and paralinguistic tags (replacing "(sighs)" brackets)

### Takeaway
No open model is in the top tier of TTS arenas. The best open-weight entry, Fish S2 Pro, is non-commercial. Among commercial-safe models, Chatterbox (Turbo and Nano) and Orpheus natively support inline paralinguistic tags (`[laugh]`/`<sigh>` style), so ElevenLabs-style tone brackets can be *mapped* rather than stripped. Kokoro has no emotion tags, so brackets must be stripped or converted into speed/voice changes.

### Cited Findings
- Arena snapshots (2026): all top-10 entries are closed-weight. Fish Audio S2 Pro is the top open-weight model at Elo about 1123-1128. One Inworld comparison put Kokoro-82M at Elo 1,059. Snapshots change weekly, and TTS-Arena-V2 had an audio-header leak that weakened its blindness. — [offlinetts aggregator](https://offlinetts.pages.dev/blog/tts-arena-leaderboard-2026/); [Inworld](https://inworld.ai/resources/best-voice-ai-tts-apis-for-real-time-voice-agents-2026-benchmarks)
- Chatterbox is ranked #12 on the arena (ELO 1518, a different scale or snapshot). Resemble's own blind test reports 65% preference over ElevenLabs Turbo (vendor-run). — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Chatterbox-Turbo/Nano tags include `[cough]`, `[laugh]`, `[chuckle]` "and more". The original 500M model has an "exaggeration" emotion-intensity control. — [chatterbox](https://github.com/resemble-ai/chatterbox)
- Orpheus tags: `<laugh>`, `<sigh>`, `<chuckle>`, `<cough>`, `<sniffle>`, `<groan>`, `<yawn>`, `<gasp>`. — [Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI). The model card says emotion can be guided "with simple tags". — [HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft)
- Qwen3-TTS-1.7B-VoiceDesign creates voices from natural-language descriptions; it is reported SOTA on InstructTTSEval (APS 82.9% English). — [Emergent Mind](https://api.emergentmind.com/topics/qwen3-tts)
- Qwen3-TTS is reported to have the lowest word error rate among open models. — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Hume Octave 2 is named the most expressive overall, but it is hosted, not open. — [ocdevel](https://ocdevel.com/blog/20250720-tts)

### Inferences
- Tag mapping layer for the existing pipeline: parse "(sighs)", "(laughs)", "(whispers)" and map them to `<sigh>`/`[laugh]` on Chatterbox or Orpheus. Map any tag the engine doesn't support to nothing, or to a prosody tweak (speed -10% for sighs). Keep the current strip-brackets path for Kokoro and Piper.
- Qwen3-TTS VoiceDesign is a strong way to *author* about 20 character timbres from text prompts ("gruff middle-aged blacksmith, low gravelly voice"), with no third-party human voice involved. Render a reference clip once per character, then clone from that clip with a runtime engine. This sidesteps voice-actor consent issues (see section 5).

### Gaps
- No independent listening-test data was found comparing Kokoro, Chatterbox-Turbo and Qwen3-TTS specifically on short in-character fantasy lines.
- Dia's non-verbal tags and Zonos's emotion vectors were not verified from primary sources in this session.

## 4. Voice cloning and giving ~20 distinct, consistent main voices plus pools for ~86 generic NPCs

### Takeaway
Two workable strategies:
- **(A) Fixed embeddings / voicepacks.** Kokoro's 54 presets plus weighted blending can produce dozens of deterministic, perfectly consistent voices. Their character range is limited (few old or gruff timbres, no true child voices).
- **(B) Zero-shot cloning from one fixed reference clip per character.** Chatterbox (7-10 s reference), Qwen3-TTS (3 s), Zonos and CosyVoice support this. It gives the widest range (old men, a gruff smith, a scheming widow), but needs a fixed seed, a fixed reference and cached outputs to stay consistent.

### Cited Findings
- Kokoro: no cloning, 54 preset voices. — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Kokoro-FastAPI voice blending: a weighted syntax such as `af_bella(2)+af_sky(1)` is normalised to 67%/33%. Mixes can be saved as `.pt` and aliased, and `/v1/audio/voices` lists the voices. — [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- Chatterbox cloning uses a reference clip of about 10 s (example file "your_10s_ref_clip.wav"). For multilingual use, the reference language should match or accent leaks in; `cfg_weight=0` is suggested as a mitigation. — [chatterbox](https://github.com/resemble-ai/chatterbox); 7-10 s reference per [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Qwen3-TTS clones from a 3 s sample; CosyVoice 3 supports zero-shot cloning; Fish S2 uses a 10-30 s reference (non-commercial). — [ocdevel](https://ocdevel.com/blog/20250720-tts)
- Orpheus: zero-shot cloning is claimed on the pretrained model. The finetuned model ships named voices (English: tara, leah, jess, leo, dan, mia, zac, zoe; community multilingual finetunes add FR/DE/KO/HI/ZH/ES/IT voices). — [HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft); [Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI)
- Supertonic exposes voice styles M1-M5 / F1-F5 (10 voices). — [NobodyWho docs](https://docs.nobodywho.ooo/godot/text-to-speech)
- VibeVoice is built for multi-speaker long form, not cloning. — [ocdevel](https://ocdevel.com/blog/20250720-tts)

### Inferences
- **Consistency recipe for zero-shot engines:** store per NPC `{engine, reference_wav (fixed), seed, temperature/cfg/exaggeration, speed}`. Precompute the speaker embedding or conditioning once, cache it, and never re-derive it from a different clip. Cache generated audio keyed by `hash(npc_id + normalized_text + params)`, which the game already does with ElevenLabs. Low temperature and a fixed seed reduce drift. Autoregressive models (Orpheus, Chatterbox) drift more than embedding-conditioned flow or StyleTTS models.
- **Kokoro recipe for 20 mains:** pick distinct base voices (bm_* British male and bf_* British female suit medieval UK-ish fantasy) and blend 2-3 voices per character. Add per-character `speed` (0.85 for old men, 1.1 for the excitable 17-year-old) and an optional pitch shift in Godot (AudioEffectPitchShift on a per-NPC bus). Kokoro voices are deterministic, so consistency is free.
- **Generic NPC pools (about 86):** about 8-12 pool voices (Kokoro blends or Piper multi-speaker models) times speed and pitch jitter seeded by `npc_id` gives the appearance of variety at no cost.
- A child-like voice is the hardest gap for Kokoro presets. Cloning from a licensed or designed reference (Qwen3 VoiceDesign, then Chatterbox) is likely required.

### Gaps
- No quantitative study was found on cloned-voice stability over hundreds of lines for Chatterbox or Qwen3-TTS.
- The exact Kokoro English voice list (names like bm_george, bf_emma) is from prior knowledge plus the NobodyWho default `bf_emma`, and needs checking against VOICES.md.

## 5. Licensing and ethics of reference voices for cloning

### Takeaway
The model licence covers the software, not the person whose voice is cloned. For a commercial game, clone only from (a) a voice actor under a written contract that explicitly grants synthetic-voice and AI rights, (b) voices you *designed* synthetically (Qwen3 VoiceDesign, Kokoro blends), or (c) datasets whose licence allows commercial derivative voice use. Never clone celebrities, or random YouTube or audiobook clips.

### Cited Findings
- Chatterbox watermarks all outputs (Perth) for provenance. — [chatterbox](https://github.com/resemble-ai/chatterbox)
- F5-TTS weights are non-commercial specifically because of their in-the-wild training data (Emilia). This shows that dataset provenance flows into licence terms. — [F5-TTS](https://github.com/SWivid/F5-TTS)

### Inferences
- Practical path: hire 3-6 voice actors on an AI-voice-licensing contract (consent, scope = this game, compensation, and a revocation or term clause). Record 30-60 s clean references per character. SAG-AFTRA's 2024-2025 interactive-media AI provisions and similar union terms are relevant if a union actor is used (not verified in this session).
- Open datasets such as LibriTTS (CC-BY-4.0) and VCTK (CC-BY-4.0) permit commercial use with attribution in general. Cloning an identifiable individual reader still raises right-of-publicity concerns (e.g. Tennessee ELVIS Act 2024, which is not verified in this session). Synthetic voice design is the lowest-risk option.
- Disclose AI-generated voice in the store page or credits. Steam's AI-content disclosure (from Jan 2024) requires it for pre-generated content, and live-generated content needs guardrails described (prior knowledge, not verified here).

### Gaps
- Specific case law, Steam disclosure policy text and union contract language were not fetched in this session.

## 6. Godot 4.5 integration paths

### Takeaway
The fastest route to parity with the current ElevenLabs flow is a **local HTTP sidecar exposing OpenAI-style `/v1/audio/speech`**. Kokoro-FastAPI is the best fit: streaming, PCM output, voice blending. Godot calls it with HTTPRequest or HTTPClient and feeds an AudioStreamGenerator, which keeps nearly all of the existing streaming and caching code. For shipping to players without Python, use a native in-engine path: the NobodyWho Godot addon (Kokoro, Pocket TTS and Supertonic via ONNX, EUPL-1.2), the godot-piper-plus addon (Piper, with streaming), or a custom GDExtension over ONNX Runtime or sherpa-onnx. Use `DisplayServer.tts_speak` only as a last-resort fallback.

### Cited Findings
- Kokoro-FastAPI offers `/v1/audio/speech` (OpenAI-client compatible, `base_url=http://localhost:8880/v1`) with mp3/wav/opus/flac/aac/pcm output and streaming, plus `/v1/audio/voices`, `/dev/captioned_speech` word timestamps and phoneme endpoints. Docker images cover CPU and CUDA (amd64/arm64) and ROCm (experimental). — [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- Orpheus-FastAPI offers `/v1/audio/speech` (WAV only, speed 0.5-1.5) in front of llama.cpp, LM Studio or GPUStack. Docker Compose bundles llama.cpp. — [Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI)
- NobodyWho (Godot) TTS supports Kokoro, Pocket TTS and Supertonic ONNX models via `NobodyWhoTextToSpeech.create(source, options)` and then `synthesize(text)`, which returns WAV bytes. Play the result with `AudioStreamWAV.load_from_buffer`. GPU is used by default and the device can be set to CPU. A bundled `res://` model folder works offline. The docs say nothing about streaming. Pocket TTS voice states are gated on HF. The addon itself is EUPL-1.2. — [NobodyWho docs](https://docs.nobodywho.ooo/godot/text-to-speech)
- godot-piper-plus: a Godot 4.4+ addon using the piper-plus C++ core. It has a PiperTTS node with sync, async and streaming synthesis and editor tools for model download. It is still in development. — [search summary of docswell/georgy results](https://docswell.com/s/yousan/ZPR266-2026-04-16-202433.md) (secondary; the repo itself was not fetched)
- sherpa-onnx is offline TTS, ASR and speaker-ID on onnxruntime with C/C++, Python, C#, Swift, Kotlin and other APIs, including KittenTTS support. No Godot binding was found. — [mcp.directory summary of sherpa-onnx](https://mcp.directory/skills/sherpa-onnx-tts)
- Runtime Text To Speech (georgy.dev) is a commercial Piper and Kokoro ONNX plugin for Unreal and Unity. Godot was not listed. — [Unreal forums](https://forums.unrealengine.com/t/runtime-text-to-speech-offline-cross-platform-tts-over-35-languages-and-900-voices-kokoro-support/2283445)
- Godot built-in TTS uses `DisplayServer.tts_get_voices_for_language()`, `tts_speak(text, voice_id)` (async) and `tts_stop()`. It must be enabled in Project Settings > Audio > General > Text to Speech. Libraries are present by default on Windows, macOS, Web, Android and iOS; Linux needs speech-dispatcher. Latency varies by OS. The docs do not cover routing output through audio buses. — [Godot docs](https://docs.godotengine.org/en/stable/tutorials/audio/text_to_speech.html)

### Inferences
- **Sidecar wiring (dev and early access):** spawn the sidecar with `OS.create_process()` on game start. Request `response_format=pcm` (24 kHz s16le for Kokoro) with streaming, read chunks via HTTPClient polling, and push frames into `AudioStreamGeneratorPlayback.push_buffer()`. That is sentence-level streaming at minimal code change versus ElevenLabs. On cache miss, write the final WAV to `user://tts_cache/`.
- **Shipping:** bundling Python and PyTorch is heavy (GBs). For players, an ONNX path (Kokoro ONNX at about 80-340 MB, Piper at about 61 MB per voice) through NobodyWho or a GDExtension wrapping onnxruntime or sherpa-onnx's C API ships much smaller and needs no server. NobodyWho's EUPL-1.2 is a weak-copyleft licence: modifications to the addon itself must be shared, but linking from a proprietary game is generally permitted. Have a lawyer confirm this.
- Built-in OS TTS output cannot reliably be routed through Godot AudioServer buses (it is OS-rendered), so it cannot be spatialised or pitch-shifted per NPC. From prior knowledge, the class reference lists volume, pitch and rate parameters on `tts_speak`; this is not verified here. Use it only as a "no-model" accessibility fallback.
- **Orpheus via the existing Ollama/llama.cpp stack:** feasible (llama.cpp server plus a SNAC decoder in Python or Rust, e.g. rlx-orpheus), but it adds a second LLM load. Ollama itself has no audio output API, so a SNAC sidecar is still required.

### Gaps
- The godot-piper-plus repository URL and licence were not verified directly.
- No Godot sherpa-onnx binding was found. Its existence is unconfirmed.
- Whether NobodyWho ships macOS arm64 binaries with Metal or CoreML acceleration was not stated.

## 7. Languages

### Takeaway
English is covered by all of them. For multilingual localisation, the commercial-safe choices are Chatterbox Multilingual V3 (23 languages), Kokoro (8 languages), Qwen3-TTS (10 languages) and Zonos (5 languages). Orpheus base is English only, with community finetunes for 7 more.

### Cited Findings
- Chatterbox Multilingual V3 covers ar, da, de, el, en, es, fi, fr, he, hi, it, ja, ko, ms, nl, no, pl, pt, ru, sv, sw, tr and zh. — [chatterbox](https://github.com/resemble-ai/chatterbox)
- Kokoro covers English US/GB, Spanish, French, Hindi, Italian, Japanese, Brazilian Portuguese and Mandarin. — [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- Qwen3-TTS supports 10 languages including Japanese. — [Gigazine](https://gigazine.net/gsc_news/en/20260123-qwen3-tts-family-opensource)
- Zonos covers EN, JA, ZH, FR and DE. — [yaps.ai](https://www.yaps.ai/blog/best-local-tts-models)
- Orpheus is English only. Lex-au community finetunes add FR, DE, KO, HI, ZH, ES and IT. — [HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft); [Orpheus-FastAPI](https://github.com/Lex-au/Orpheus-FastAPI)
- Fish S2 claims 80+ languages, but top quality only in JA, EN and ZH (non-commercial). — [ocdevel](https://ocdevel.com/blog/20250720-tts)

### Inferences
- Keeping one character's voice consistent across languages needs a cloning engine (Chatterbox ML, Qwen3). Kokoro voices are language-specific.

### Gaps
- Piper language coverage was not checked here (prior knowledge: 30+ languages, with per-voice licences).

## 8. Recommendation by tier

### Takeaway
- **Tier 1, default (dev M4 and all players):** Kokoro-82M (Apache-2.0). Run it as a Kokoro-FastAPI sidecar during development, then ship it in-engine via ONNX (NobodyWho or a custom GDExtension). Make the 20 mains from blended voicepacks with per-NPC speed and pitch, and the generic pools from seeded jitter. Strip the tone brackets.
- **Tier 2, expressive and cloned (players with a GPU of 6 GB+ VRAM, or the M4):** Chatterbox-Turbo (MIT, watermarked), with fixed reference clips per main NPC and tone brackets mapped to `[laugh]`-style tags. Qwen3-TTS-0.6B/1.7B (Apache-2.0) is a strong alternative with the best voice *design* for authoring timbres. Pre-render and cache scripted lines; use live synthesis only for dynamic LLM lines.
- **Tier 3, CPU-only or low-end:** Piper (Rhasspy MIT build, voice licences checked per voice; avoid the GPLv3 OHF fork in a proprietary build), Pocket TTS, Supertonic 2 (check OpenRAIL-M), Kitten TTS (Apache-2.0) or Chatterbox-Nano. Fall back to `DisplayServer.tts_speak`.
- **Avoid for commercial shipping:** XTTS-v2, F5-TTS weights, Spark-TTS, Fish S2 / OpenAudio, IndexTTS and Higgs V3 (non-commercial). Orpheus is technically excellent at tags, but it is a 3B LLM competing with the game's LLM and carries Llama-licence ambiguity. Use it only after legal review and on 16 GB+ GPUs.

### Cited Findings
- The supporting evidence is in sections 1-7 above, chiefly [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI), [Chatterbox](https://github.com/resemble-ai/chatterbox), [Picovoice](https://picovoice.ai/blog/on-device-tts/), [F5-TTS](https://github.com/SWivid/F5-TTS), [Orpheus HF](https://huggingface.co/canopylabs/orpheus-3b-0.1-ft) and [Cartesia licence list](https://www.cartesia.ai/learn/open-source-tts).

### Inferences
- **Hybrid architecture:** a `TTSProvider` interface in Godot with backends {ElevenLabs (optional, BYOK), Kokoro-sidecar, Kokoro-ONNX-native, Chatterbox-sidecar, OS-TTS}. A per-NPC voice profile maps each backend to its own voice spec, sharing the existing text normalisation (bracket strip or map) and the audio cache keyed by `(npc_id, text, backend, params)`.
- Pre-generating a large share of the main NPCs' scripted or common lines at build time with the highest-quality commercial-safe engine (Chatterbox or Qwen3), and synthesising only dynamic LLM lines live with Kokoro, gives the best quality-to-latency ratio. The cost is a possible timbre mismatch, so use the same engine per NPC where possible.

### Gaps
- An M4 benchmark of Kokoro, Chatterbox-Turbo, Qwen3-TTS-0.6B and Orpheus-Q4 GGUF running alongside a concurrently loaded 8-14B LLM is the key missing measurement. Run it before committing to Tier 2 on the M4.
