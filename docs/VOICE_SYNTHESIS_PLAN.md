# Voice Synthesis Integration Plan

> **Document Purpose:** Technical plan for integrating ElevenLabs TTS into NPC dialogue
> **Status:** Research Complete
> **API:** ElevenLabs Text-to-Speech

---

## API Overview

### Endpoints

| Endpoint | URL | Use Case |
|----------|-----|----------|
| **Standard TTS** | `POST /v1/text-to-speech/{voice_id}` | Pre-generate audio files |
| **Streaming TTS** | `POST /v1/text-to-speech/{voice_id}/stream` | Real-time dialogue playback |

**Base URL:** `https://api.elevenlabs.io`

### Authentication

```
Header: xi-api-key: <your_api_key>
```

### Request Body

```json
{
  "text": "Dialogue text here",
  "model_id": "eleven_multilingual_v2",
  "output_format": "mp3_44100_128",
  "voice_settings": {
    "stability": 0.5,
    "similarity_boost": 0.75,
    "style": 0.0,
    "speed": 1.0,
    "use_speaker_boost": true
  }
}
```

### Output Formats

| Format | Quality | Use Case |
|--------|---------|----------|
| `mp3_44100_128` | High quality | Pre-generated files |
| `mp3_22050_32` | Lower quality | Streaming, smaller files |
| `pcm_16000` | Raw PCM | Direct playback in Godot |
| `opus_48000_64` | Good compression | Web streaming |

---

## Pricing & Limits

| Tier | Credits/Month | Characters | Cost |
|------|---------------|------------|------|
| **Free** | 10,000-20,000 | ~10 min audio | $0 |
| **Starter** | 30,000 | ~30 min audio | $5/mo |
| **Creator** | 100,000 | ~100 min audio | $22/mo |
| **Pro** | 500,000 | ~500 min audio | $99/mo |

**Rate:** ~1 credit per character (for multilingual v2 model)

### Per-Request Limits

- Free tier: 2,500 characters max per request
- Paid tiers: 5,000 characters max per request

---

## Voice Assignment Strategy

### NPC Voice Profiles

| NPC | Voice Type | Suggested Settings |
|-----|------------|-------------------|
| **Gregor** | Middle-aged male, warm but nervous | stability: 0.4, similarity: 0.8 |
| **Elena** | Young female, gentle, curious | stability: 0.6, similarity: 0.7 |
| **Mira** | Adult female, guarded, weary | stability: 0.5, similarity: 0.75 |
| **Bjorn** | Deep male, gruff, honest | stability: 0.7, similarity: 0.8 |
| **Aldric** | Authoritative male, military | stability: 0.8, similarity: 0.75 |
| **Mathias** | Elderly male, wise, measured | stability: 0.6, similarity: 0.7 |
| **Varn** | Menacing male, cold, threatening | stability: 0.5, similarity: 0.85 |

### Voice Selection Options

1. **Pre-made voices** - Use ElevenLabs library voices (free)
2. **Voice cloning (IVC)** - Clone from sample audio (paid tiers)
3. **Professional cloning (PVC)** - High-quality custom voices (higher tiers)

---

## Implementation Architecture

### Option A: Pre-Generated Audio (Recommended for MVP)

```
[Claude Response] -> [Cache Check] -> [ElevenLabs API] -> [MP3 File] -> [AudioStreamPlayer]
```

**Pros:**
- Simpler implementation
- Cacheable responses
- Works offline after generation

**Cons:**
- Latency on first play
- Storage requirements
- API calls for each unique line

### Option B: Streaming Audio (Future Enhancement)

```
[Claude Response] -> [ElevenLabs Stream] -> [AudioStreamPlayer] (real-time)
```

**Pros:**
- Lower latency perception
- No storage needed

**Cons:**
- Requires continuous connection
- More complex buffering
- Higher API usage

---

## GDScript Implementation

### ElevenLabs Client

```gdscript
# scripts/audio/elevenlabs_client.gd
extends Node
class_name ElevenLabsClient

const BASE_URL = "https://api.elevenlabs.io/v1"
var api_key: String = ""
var http_request: HTTPRequest

signal audio_ready(audio_data: PackedByteArray, npc_id: String)
signal audio_error(error: String)

func _ready():
    http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(_on_request_completed)

    # Load API key from environment or config
    api_key = OS.get_environment("ELEVENLABS_API_KEY")

func generate_speech(text: String, voice_id: String, npc_id: String):
    var url = "%s/text-to-speech/%s" % [BASE_URL, voice_id]

    var headers = [
        "xi-api-key: %s" % api_key,
        "Content-Type: application/json"
    ]

    var body = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "output_format": "mp3_22050_32",
        "voice_settings": {
            "stability": 0.5,
            "similarity_boost": 0.75
        }
    }

    # Store npc_id for callback
    http_request.set_meta("npc_id", npc_id)

    var error = http_request.request(
        url,
        headers,
        HTTPClient.METHOD_POST,
        JSON.stringify(body)
    )

    if error != OK:
        audio_error.emit("Failed to send request: %s" % error)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
    var npc_id = http_request.get_meta("npc_id", "unknown")

    if response_code == 200:
        audio_ready.emit(body, npc_id)
    else:
        audio_error.emit("API error %d: %s" % [response_code, body.get_string_from_utf8()])
```

### Voice Manager

```gdscript
# scripts/audio/voice_manager.gd
extends Node

# Voice ID mapping for each NPC
var voice_mapping := {
    "gregor_001": "voice_id_here",
    "elena_daughter_001": "voice_id_here",
    "mira_tavern_001": "voice_id_here",
    "bjorn_blacksmith_001": "voice_id_here",
    "aldric_captain_001": "voice_id_here",
    "mathias_elder_001": "voice_id_here",
    "varn_bandit_001": "voice_id_here"
}

# Audio cache to avoid regenerating same lines
var audio_cache := {}  # hash(text + voice_id) -> audio_data

@onready var elevenlabs: ElevenLabsClient = $ElevenLabsClient
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

func speak(npc_id: String, text: String):
    var voice_id = voice_mapping.get(npc_id, "")
    if voice_id.is_empty():
        push_warning("No voice mapped for NPC: %s" % npc_id)
        return

    var cache_key = (text + voice_id).hash()

    if audio_cache.has(cache_key):
        _play_audio(audio_cache[cache_key])
    else:
        elevenlabs.generate_speech(text, voice_id, npc_id)

func _on_audio_ready(audio_data: PackedByteArray, npc_id: String):
    # Cache the audio
    var cache_key = (current_text + voice_mapping[npc_id]).hash()
    audio_cache[cache_key] = audio_data

    _play_audio(audio_data)

func _play_audio(data: PackedByteArray):
    var stream = AudioStreamMP3.new()
    stream.data = data
    audio_player.stream = stream
    audio_player.play()
```

### Integration with Dialogue UI

```gdscript
# In dialogue_ui.gd
func _on_npc_response_received(npc_id: String, response: String):
    # Display text
    dialogue_text.text = response

    # Strip tone brackets for speech: "[warmly] Hello" -> "Hello"
    var clean_text = _strip_tone_brackets(response)

    # Generate and play voice
    if VoiceManager:
        VoiceManager.speak(npc_id, clean_text)

func _strip_tone_brackets(text: String) -> String:
    var regex = RegEx.new()
    regex.compile("\\[.*?\\]\\s*")
    return regex.sub(text, "", true)
```

---

## Cost Estimation

### Per Session (Estimated)

| Scenario | Lines | Avg Characters | Total Chars | Cost (Starter) |
|----------|-------|----------------|-------------|----------------|
| Short conversation | 5 | 100 | 500 | ~500 credits |
| Medium conversation | 15 | 150 | 2,250 | ~2,250 credits |
| Long conversation | 30 | 150 | 4,500 | ~4,500 credits |

### Monthly Budget (Starter Tier - 30,000 credits)

- ~13 medium conversations per month
- ~6 long conversations per month

### Optimization Strategies

1. **Cache aggressively** - Store generated audio locally
2. **Batch generation** - Pre-generate common greetings
3. **Text truncation** - Limit response length for voice
4. **Selective voicing** - Only voice key story moments
5. **Local fallback** - Use Godot TTS for less important lines

---

## Implementation Phases

### Phase 1: Basic Integration

- [ ] Create ElevenLabsClient singleton
- [ ] Implement API key configuration
- [ ] Add voice_id mapping for NPCs
- [ ] Basic audio playback in DialogueUI

### Phase 2: Caching & Optimization

- [ ] Implement audio cache (memory)
- [ ] Add disk cache for persistence
- [ ] Strip tone brackets before TTS
- [ ] Add loading indicator during generation

### Phase 3: Voice Selection

- [ ] Research available pre-made voices
- [ ] Assign voices to each NPC
- [ ] Tune voice_settings per character
- [ ] Consider voice cloning for unique NPCs

### Phase 4: Polish

- [ ] Add audio queue for longer responses
- [ ] Implement streaming for lower latency
- [ ] Add voice toggle in settings
- [ ] Subtitle sync with audio timing

---

## Alternative: Local TTS (Fallback)

Godot has built-in TTS via `DisplayServer`:

```gdscript
# Basic local TTS (no unique voices, but free)
DisplayServer.tts_speak(text, voice_id, volume, pitch, rate)
var voices = DisplayServer.tts_get_voices()
```

**Use for:**
- Development/testing
- Offline fallback
- Non-critical NPC lines

---

## Security Notes

1. **Never commit API key** - Use environment variables
2. **Rate limiting** - Implement client-side throttling
3. **Error handling** - Graceful fallback when API fails
4. **Usage monitoring** - Track credits used per session

---

## Sources

- [ElevenLabs API Pricing](https://elevenlabs.io/pricing/api)
- [ElevenLabs Text-to-Speech Docs](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
- [ElevenLabs Streaming Docs](https://elevenlabs.io/docs/api-reference/text-to-speech/stream)
- [ElevenLabs Voice Management](https://elevenlabs.io/docs/api-reference/voices)
