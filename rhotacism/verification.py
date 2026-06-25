import re
import numpy as np
from .models import AudioInput, VerificationResult

# Edit distance ≤ 1 catches single-phoneme Whisper transcription noise
# and also accepts productions like "wed" when the user attempted "red"
# (rhotacism means they genuinely produced a near-miss, not the wrong word).
MAX_EDIT_DISTANCE = 1


def load_verifier():
    """Load Whisper-base.en once at server startup."""
    import whisper
    return whisper.load_model("base.en")


def verify_word(
    audio: AudioInput,
    target_word: str,
    model,
) -> VerificationResult:
    """
    Transcribe audio with Whisper and check whether the user said target_word.
    Returns VerificationResult with verified=False (not an error) when the
    wrong word is detected — the caller decides whether to reject the request.
    """
    result = model.transcribe(audio.array, language="en", fp16=False)
    transcription: str = result.get("text", "").strip()

    segments = result.get("segments", [])
    if segments:
        no_speech_prob = segments[0].get("no_speech_prob", 0.0)
        base_confidence = round(1.0 - no_speech_prob, 3)
    else:
        # No speech segments → silence or very short utterance
        return VerificationResult(
            verified=False,
            transcription=transcription,
            confidence=0.0,
        )

    norm_target = _normalise(target_word)
    norm_words = [_normalise(w) for w in transcription.split() if _normalise(w)]

    # Exact match
    if norm_target in norm_words:
        return VerificationResult(
            verified=True,
            transcription=transcription,
            confidence=base_confidence,
        )

    # Fuzzy match — single edit covers common Whisper noise on short words
    for word in norm_words:
        if _edit_distance(norm_target, word) <= MAX_EDIT_DISTANCE:
            return VerificationResult(
                verified=True,
                transcription=transcription,
                confidence=round(base_confidence * 0.8, 3),
            )

    return VerificationResult(
        verified=False,
        transcription=transcription,
        confidence=base_confidence,
    )


def _normalise(text: str) -> str:
    return re.sub(r"[^a-z]", "", text.lower())


def _edit_distance(a: str, b: str) -> int:
    if len(a) < len(b):
        a, b = b, a
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for ca in a:
        curr = [prev[0] + 1]
        for j, cb in enumerate(b):
            curr.append(min(prev[j + 1] + 1, curr[j] + 1, prev[j] + (ca != cb)))
        prev = curr
    return prev[-1]
