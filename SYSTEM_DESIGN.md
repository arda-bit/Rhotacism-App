# Rhotacism Therapy Backend — System Design

## 1. Overview

A server-side pipeline that accepts a target word and a short audio recording from
an iOS client, determines whether the speaker produced a correct English /r/ phoneme,
classifies the error type if not, and returns structured feedback to guide correction.

All models are open-source and run on-premises. No per-request API fees.

---

## 2. High-Level Architecture

```
iOS Client
    │
    │  POST /analyze
    │  { target_word: "red", audio: <m4a bytes> }
    ▼
┌─────────────────────────────────────────────────────┐
│  FastAPI Server  (server.py)                        │
│                                                     │
│  Stage 1: Audio Ingestion & Preprocessing           │
│      load_audio() → validate_audio() → preprocess() │
│              ↓                                      │
│  Stage 2: Word Verification  (Whisper-base.en)      │
│      verify_word()                                  │
│              ↓                                      │
│  Stage 3: Phoneme Forced Alignment  (MMS FA)        │
│      find_r_segment()                               │
│              ↓                                      │
│  Stage 4: Formant Extraction  (parselmouth / Praat) │
│      extract_formants()                             │
│              ↓                                      │
│  Stage 5: Error Classification  (rule-based)        │
│      classify()                                     │
│              ↓                                      │
│  Stage 6: Feedback Generation  (rule-based)         │
│      generate_feedback()                            │
└─────────────────────────────────────────────────────┘
    │
    │  { error_type, rhoticity_score, feedback, cue }
    ▼
iOS Client
```

---

## 3. Project Structure

```
rhotacism-app/
├── SYSTEM_DESIGN.md
├── pyproject.toml
├── server.py                   # FastAPI app + lifespan model loading
├── rhotacism/
│   ├── __init__.py
│   ├── models.py               # Shared dataclasses and enums
│   ├── audio.py                # Stage 1
│   ├── verification.py         # Stage 2
│   ├── alignment.py            # Stage 3
│   ├── formants.py             # Stage 4
│   ├── classifier.py           # Stage 5
│   ├── feedback.py             # Stage 6
│   └── words.py                # Word lists and progression logic
└── tests/
    ├── conftest.py             # Shared fixtures
    ├── test_audio.py           # Stage 1 tests
    ├── test_verification.py    # Stage 2 tests
    ├── test_alignment.py       # Stage 3 tests
    ├── test_formants.py        # Stage 4 tests
    ├── test_classifier.py      # Stage 5 tests
    └── test_feedback.py        # Stage 6 tests
```

---

## 4. Shared Data Models (`rhotacism/models.py`)

```python
from dataclasses import dataclass
from enum import Enum
import numpy as np

class ErrorType(str, Enum):
    CORRECT        = "correct"
    W_SUBSTITUTION = "w_substitution"   # /w/ for /r/ — most common
    L_SUBSTITUTION = "l_substitution"   # /l/ for /r/
    PARTIAL        = "partial"           # F3 in transition zone
    UNCLEAR        = "unclear"           # segment too short / noisy

@dataclass
class AudioInput:
    array: np.ndarray   # float32, mono
    sample_rate: int    # always 16000

@dataclass
class VerificationResult:
    verified:      bool
    transcription: str
    confidence:    float  # 0.0–1.0

@dataclass
class PhonemeSegment:
    phoneme:    str
    start_time: float  # seconds
    end_time:   float  # seconds

@dataclass
class FormantMeasurement:
    f1:       float  # Hz
    f2:       float  # Hz
    f3:       float  # Hz
    f2_slope: float  # positive = rising, negative = falling
    duration: float  # seconds

@dataclass
class ClassificationResult:
    error_type:      ErrorType
    rhoticity_score: float  # 0.0 (non-rhotic) → 1.0 (fully rhotic)
    f3_hz:           float
    confidence:      float

@dataclass
class FeedbackResult:
    message:  str
    cue:      str
    score:    float
    level_up: bool
```

---

## 5. Stage 1 — Audio Ingestion & Preprocessing

### Purpose
Accept any audio format from iOS (typically `.m4a` / AAC), convert to the
16 kHz mono float32 array required by every downstream stage, apply noise
reduction, and trim silence.

### Module: `rhotacism/audio.py`

### Public Interface
```python
def load_audio(file_bytes: bytes, fmt: str | None = None) -> AudioInput
def validate_audio(audio: AudioInput) -> None          # raises ValueError
def preprocess(audio: AudioInput) -> AudioInput
```

### Constants
| Name | Value | Reason |
|---|---|---|
| `SAMPLE_RATE` | 16000 | Required by Wav2Vec2 / MMS |
| `MIN_DURATION` | 0.5 s | Below this, no phoneme can be reliably extracted |
| `MAX_DURATION` | 10.0 s | Prevents runaway inference on accidental long recordings |
| `NOISE_PROP_DECREASE` | 0.8 | Aggressive enough to clean mic noise without robotic artefacts |
| `SILENCE_TOP_DB` | 25 | Trim anything 25 dB below peak |

### Implementation Notes
- `pydub.AudioSegment.from_file()` uses ffmpeg internally and handles m4a, webm, wav, mp3 transparently.
- Normalise to `[-1.0, 1.0]` by dividing int16 samples by 32768.
- `noisereduce` with `stationary=True` targets constant background hum (typical for quiet indoor environments).
- `librosa.effects.trim` removes leading/trailing silence so the model's CTC alignment starts at the first phoneme.

### Unit Tests: `tests/test_audio.py`

```python
class TestLoadAudio:
    def test_wav_returns_16khz_mono_float32(self): ...
    def test_normalises_amplitude_to_unit_range(self): ...
    def test_stereo_input_converted_to_mono(self): ...
    def test_higher_sample_rate_resampled_down(self): ...

class TestValidateAudio:
    def test_valid_duration_passes(self): ...
    def test_below_min_duration_raises_value_error(self): ...
    def test_above_max_duration_raises_value_error(self): ...
    def test_wrong_sample_rate_raises_value_error(self): ...

class TestPreprocess:
    def test_returns_audio_input_type(self): ...
    def test_output_shorter_or_equal_to_input(self): ...
    def test_sample_rate_preserved(self): ...
    def test_silent_padding_trimmed(self): ...
```

### Acceptance Criteria
- [ ] `.m4a` and `.wav` files both load without error (requires ffmpeg installed)
- [ ] Output is always `float32`, mono, `sample_rate == 16000`
- [ ] All four `TestValidateAudio` tests pass
- [ ] Preprocessing does not crash on a pure-silence array

---

## 6. Stage 2 — Word Verification

### Purpose
Confirm the user actually said the target word before committing expensive
alignment and formant extraction. Reject off-topic or silent recordings early.

### Model: `openai/whisper-base.en`
| Property | Value |
|---|---|
| Parameters | 39 M |
| Disk | ~150 MB |
| Latency (CPU) | ~0.4–0.8 s on a 3 s clip |
| License | MIT |

### Module: `rhotacism/verification.py`

### Public Interface
```python
def load_verifier() -> whisper.Whisper           # call once at server startup
def verify_word(
    audio: AudioInput,
    target_word: str,
    model: whisper.Whisper,
) -> VerificationResult
```

### Matching Logic
Whisper transcribes freely. Match by checking if the target word appears as a
substring after normalising both to lowercase and stripping punctuation.
A fuzzy match (edit-distance ≤ 1) handles minor transcription noise.

### Unit Tests: `tests/test_verification.py`

```python
# All tests mock the Whisper model to avoid loading 150 MB in CI.
class TestVerifyWord:
    def test_correct_word_returns_verified_true(self): ...
    def test_wrong_word_returns_verified_false(self): ...
    def test_transcription_case_insensitive(self): ...
    def test_fuzzy_match_within_edit_distance_1(self): ...
    def test_empty_transcription_returns_false(self): ...
    def test_result_contains_transcription_string(self): ...
```

### Acceptance Criteria
- [ ] Returns `verified=True` when user says the target word
- [ ] Returns `verified=False` for silence or a completely different word
- [ ] Does not raise on an array of zeros (silence)

---

## 7. Stage 3 — Phoneme Forced Alignment

### Purpose
Locate the exact time window within the recording where the /r/ phoneme
occurs. Passing the full utterance to formant extraction would average
across all phonemes and give meaningless F3 values.

### Model: `torchaudio` MMS Forced Aligner (`MMS_FA` pipeline)
| Property | Value |
|---|---|
| Base model | Meta MMS (Massively Multilingual Speech) |
| Disk | ~300 MB (downloaded on first use) |
| Latency (CPU) | ~0.5–1.0 s on a 3 s clip |
| License | CC-BY-NC 4.0 |

### Module: `rhotacism/alignment.py`

### Public Interface
```python
def load_aligner() -> torchaudio.pipelines.Aligner   # call once at server startup
def find_r_segment(
    audio: AudioInput,
    aligner,
) -> PhonemeSegment | None    # None if no /r/ token found
```

### Implementation Notes
- MMS FA operates on IPA tokens. The rhotic approximant maps to `ɹ`.
- Minimum segment duration: 30 ms. Shorter windows produce unreliable formants.
- If no `ɹ` is found (correct for non-rhotic recordings too), the absence itself
  is diagnostic — return `None` and the classifier handles the UNCLEAR case.

### Unit Tests: `tests/test_alignment.py`

```python
# Mock the aligner to return synthetic token sequences.
class TestFindRSegment:
    def test_returns_phoneme_segment_when_r_present(self): ...
    def test_returns_none_when_no_r_token(self): ...
    def test_segment_times_are_positive(self): ...
    def test_segment_end_greater_than_start(self): ...
    def test_minimum_duration_enforced(self): ...
    def test_phoneme_field_is_r_variant(self): ...
```

### Acceptance Criteria
- [ ] Returns a `PhonemeSegment` with `end_time > start_time`
- [ ] Returns `None` for audio containing no /r/-like token
- [ ] Segment duration ≥ 30 ms

---

## 8. Stage 4 — Formant Extraction

### Purpose
Measure F1, F2, and F3 within the aligned /r/ segment.
F3 depression below ~2100 Hz is the primary acoustic correlate of English
rhoticity (Lehiste 1964; Stevens 1998).

### Tool: `parselmouth` (Python bindings for Praat)
| Property | Value |
|---|---|
| Type | Signal processing — no ML model |
| Disk | ~20 MB |
| Latency | ~50 ms |
| License | GPL-3.0 |

### Module: `rhotacism/formants.py`

### Public Interface
```python
def extract_formants(
    audio: AudioInput,
    segment: PhonemeSegment,
) -> FormantMeasurement
```

### Praat Parameters
| Parameter | Value | Reason |
|---|---|---|
| Max formants | 5 | Standard for formant analysis |
| Max frequency | 5500 Hz | Adult male/female range (lower = 5000 for children) |
| Window length | 25 ms | Standard Praat default |
| Pre-emphasis | 50 Hz | Flatten low-frequency dominance |

### F2 Slope Calculation
Sample F2 at 25%, 50%, and 75% of the segment duration. Slope = F2(75%) − F2(25%).
- Positive slope → F2 rising → /w/-like coarticulation
- Slope near zero → lateral or no movement

### Unit Tests: `tests/test_formants.py`

```python
class TestExtractFormants:
    def test_returns_formant_measurement(self): ...
    def test_f3_positive(self): ...
    def test_f1_below_f2_below_f3(self): ...     # physical constraint
    def test_segment_too_short_raises(self): ...
    def test_f2_slope_sign_on_known_signal(self): ...
    def test_duration_matches_segment(self): ...
```

### Acceptance Criteria
- [ ] Returns `FormantMeasurement` with `f1 < f2 < f3` (physical constraint)
- [ ] Raises `ValueError` for segments shorter than 30 ms
- [ ] `duration` field matches `segment.end_time - segment.start_time` ± 5 ms

---

## 9. Stage 5 — Error Classification

### Purpose
Map the formant measurement to an `ErrorType` and a continuous `rhoticity_score`.
This stage is entirely rule-based — deterministic, no model, unit-testable
without any fixtures.

### Module: `rhotacism/classifier.py`

### Public Interface
```python
def classify(measurement: FormantMeasurement) -> ClassificationResult
```

### Decision Logic

```
F3 < 2100 Hz
    → CORRECT,  score = 1.0

2100 ≤ F3 < 2300 Hz
    → PARTIAL,  score = linear interpolation 0.3–0.7

F3 ≥ 2300 Hz AND f2_slope > +80 Hz
    → W_SUBSTITUTION, score = 0.0–0.2

F3 ≥ 2300 Hz AND f2_slope ≤ +80 Hz
    → L_SUBSTITUTION, score = 0.0–0.2

measurement unavailable (None passed from Stage 3)
    → UNCLEAR, score = 0.0
```

Confidence is set to 0.9 when F3 is clearly in a single zone (< 2000 or > 2500),
and 0.6 in the transition zone (2100–2300 Hz).

### Unit Tests: `tests/test_classifier.py`

```python
class TestClassify:
    def test_low_f3_returns_correct(self): ...
    def test_high_f3_rising_f2_returns_w_substitution(self): ...
    def test_high_f3_flat_f2_returns_l_substitution(self): ...
    def test_transition_zone_returns_partial(self): ...
    def test_score_between_0_and_1(self): ...
    def test_correct_score_is_1(self): ...
    def test_w_substitution_score_below_0_3(self): ...
    def test_partial_score_between_0_3_and_0_7(self): ...
    def test_confidence_high_outside_transition_zone(self): ...
    def test_confidence_lower_in_transition_zone(self): ...
```

### Acceptance Criteria
- [ ] All ten classifier tests pass with no fixtures or mocks
- [ ] `rhoticity_score` is always in `[0.0, 1.0]`
- [ ] F3 = 1800 Hz → CORRECT; F3 = 2800 Hz + rising F2 → W_SUBSTITUTION

---

## 10. Stage 6 — Feedback Generation

### Purpose
Convert the classification result into a human-readable message and a specific
articulatory cue. Also determine whether the user has unlocked the next level.

### Module: `rhotacism/feedback.py`

### Public Interface
```python
def generate_feedback(
    result: ClassificationResult,
    target_word: str,
    session_scores: list[float],   # all scores this session, newest last
) -> FeedbackResult
```

### Feedback Map
| ErrorType | Message | Articulatory Cue |
|---|---|---|
| CORRECT | "Great /r/ on '{word}'!" | "Keep your lips neutral and tongue tip curled slightly." |
| W_SUBSTITUTION | "Almost — your lips are rounding." | "Square your lips and press the sides of your tongue against your upper back teeth." |
| L_SUBSTITUTION | "Close — watch your tongue tip." | "Don't let your tongue touch the roof of your mouth. Curl it back without contact." |
| PARTIAL | "Getting there — hold the /r/ a bit longer." | "Sustain the tongue position through the vowel that follows." |
| UNCLEAR | "Recording unclear — try again in a quieter space." | "" |

### Level-Up Logic
`level_up = True` when the last 3 consecutive scores are all ≥ 0.8.

### Unit Tests: `tests/test_feedback.py`

```python
class TestGenerateFeedback:
    def test_correct_result_positive_message(self): ...
    def test_w_substitution_lip_cue_in_output(self): ...
    def test_l_substitution_tongue_cue_in_output(self): ...
    def test_partial_sustain_cue_in_output(self): ...
    def test_unclear_suggests_quieter_space(self): ...
    def test_level_up_after_three_consecutive_high_scores(self): ...
    def test_no_level_up_with_mixed_scores(self): ...
    def test_no_level_up_with_only_two_high_scores(self): ...
    def test_score_propagated_to_result(self): ...
    def test_target_word_appears_in_correct_message(self): ...
```

### Acceptance Criteria
- [ ] All ten feedback tests pass
- [ ] `level_up` is `True` only when the last 3 scores are ≥ 0.8
- [ ] Every `ErrorType` has a non-empty `message` and `cue`

---

## 11. API Layer (`server.py`)

### Endpoints

#### `POST /analyze`
```
Content-Type: multipart/form-data
Fields:
    audio       File    Audio recording (m4a, wav, webm)
    target_word string  The word the user was prompted to say
    session_scores string  JSON array of prior scores this session (optional)
```

Response `200 OK`:
```json
{
    "target_word":      "red",
    "verified":         true,
    "transcription":    "red",
    "error_type":       "w_substitution",
    "rhoticity_score":  0.12,
    "message":          "Almost — your lips are rounding.",
    "cue":              "Square your lips and press the sides...",
    "level_up":         false
}
```

Error responses:
- `400` — audio too short/long, wrong word said, file unreadable
- `422` — missing required field
- `500` — internal inference failure

#### `GET /health`
```json
{ "status": "ok", "models_loaded": true }
```

### Model Lifecycle
Models are loaded once inside a FastAPI `lifespan` context manager and stored
in `app.state`. Inference runs in a `ThreadPoolExecutor` via
`asyncio.run_in_executor` to avoid blocking the async event loop.

---

## 12. Word Progression System (`rhotacism/words.py`)

```
Level 1 — Initial /r/   red, run, rabbit, rain, robot, ring, river, road
Level 2 — Medial /r/    very, carry, forest, orange, around, parrot
Level 3 — Final /r/     car, far, floor, door, four, more
Level 4 — Clusters      green, brown, three, bring, friend, dress
```

Level-up threshold: 3 consecutive scores ≥ 0.8 at the current level.

---

## 13. Dependencies

```toml
# Inference
"openai-whisper>=20240930"    # Stage 2 — word verification
"torchaudio>=2.0.0"           # Stage 3 — forced alignment
"parselmouth>=0.4.3"          # Stage 4 — formant extraction

# Audio
"pydub>=0.25.1"               # format conversion (m4a → wav)
"noisereduce>=3.0.3"          # Stage 1 — noise reduction
"librosa>=0.11.0"             # Stage 1 — silence trimming

# Server
"fastapi>=0.100.0"
"uvicorn>=0.23.0"
"python-multipart>=0.0.6"

# Existing
"torch>=2.12.1"
"numpy>=2.4.6"

# Dev
"pytest>=8.0"
"pytest-asyncio>=0.23"
```

System requirement: **ffmpeg** must be installed (`brew install ffmpeg`).

---

## 14. Cost Estimation

| Scale | Infrastructure | Monthly cost | Notes |
|---|---|---|---|
| Dev / MVP | Local machine | $0 | CPU inference, ~1.5 s/request |
| < 100 users | Hetzner CPX31 (4 vCPU, 8 GB) | ~$16 | ~5 concurrent requests |
| 100–1 000 users | Hetzner CCX33 (8 vCPU, 32 GB) | ~$80 | ~20 concurrent |
| 1 000+ users | Vast.ai A4000 GPU | ~$150–200 | < 0.5 s/request |

**Per-request cost at small scale** (1 000 req/day on $16/mo): **~$0.0005** — negligible.

No per-call model API fees. All inference is on-premises.

---

## 15. Build & Verify Order

Each stage is independently testable before the next is implemented.

```
Stage 1 → pytest tests/test_audio.py        (no model downloads)
Stage 2 → pytest tests/test_verification.py (mocked Whisper)
Stage 3 → pytest tests/test_alignment.py    (mocked MMS aligner)
Stage 4 → pytest tests/test_formants.py     (parselmouth + synthetic audio)
Stage 5 → pytest tests/test_classifier.py   (pure functions, no fixtures)
Stage 6 → pytest tests/test_feedback.py     (pure functions, no fixtures)
Final   → pytest                            (full suite)
```
