import re
import numpy as np
from .models import AudioInput, VerificationResult

MAX_EDIT_DISTANCE = 1

# Phonemes patients commonly substitute for /r/ in rhotacism and lambdacism.
# Used to generate all plausible impaired productions of a target word so that
# Whisper's transcription of the impaired speech ("wed", "fwend", "thwee") is
# accepted as a genuine attempt at the target ("red", "friend", "three").
_R_SUBSTITUTIONS = ("w", "l", "")


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

    # Impairment-aware match.
    # Generate all plausible impaired productions of the target word
    # (r→w, r→l, r→deleted) and accept the attempt if Whisper's transcription
    # lands within one edit of any variant.  This catches:
    #   "wed"   for "red"    (r→w, variant "wed",   distance 0)
    #   "fwend" for "friend" (r→w, variant "fwiend", distance 1 — delete i)
    #   "thwee" for "three"  (r→w, variant "thwee",  distance 0)
    #   "wabbit" for "rabbit" (r→w, variant "wabbit", distance 0)
    for variant in _r_variants(norm_target):
        for word in norm_words:
            if _edit_distance(variant, word) <= MAX_EDIT_DISTANCE:
                return VerificationResult(
                    verified=True,
                    transcription=transcription,
                    confidence=round(base_confidence * 0.85, 3),
                )

    # General fuzzy fallback — catches single-phoneme Whisper transcription noise
    # on words where no /r/ substitution is in play.
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


def _r_variants(word: str) -> list[str]:
    """
    Return all plausible impaired productions of `word`.
    Replaces every /r/ with each substitution in _R_SUBSTITUTIONS so that
    Whisper's transcription of impaired speech is matched against what a
    patient with rhotacism or lambdacism would actually produce.
    """
    variants: set[str] = {word}
    if "r" in word:
        for sub in _R_SUBSTITUTIONS:
            variants.add(word.replace("r", sub))
    return list(variants)


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
