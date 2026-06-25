"""
Free-speech impairment analysis pipeline.

Accepts any audio utterance (no target word required) and returns a SpeechReport
with per-phoneme acoustic findings and per-impairment severity scores.

Limitation: greedy CTC decoding finds phonemes the speaker *produced*.
A complete /r/→/w/ substitution will register as a /w/ frame, not /r/,
so the rhotacism score reflects *quality* of attempted /r/ productions,
not the *rate* of substitution.  Full substitution detection requires
G2P + forced alignment (a future extension).
"""

from collections import defaultdict

from .models import (
    AudioInput, ImpairmentType, ErrorType,
    PhonemeResult, SpeechReport,
)
from .alignment import find_all_phoneme_segments
from .formants  import extract_formants
from .spectral  import extract_sibilant_cog
from .classifier import classify, classify_sibilant

# Map MMS phoneme token → impairment domain
_PHONEME_DOMAIN: dict[str, ImpairmentType] = {
    "r": ImpairmentType.RHOTACISM,
    "s": ImpairmentType.SIGMATISM,
    "z": ImpairmentType.SIGMATISM,
    "l": ImpairmentType.LAMBDACISM,
}

# Anything below this mean score is flagged as a concern
_CONCERN_THRESHOLD = 0.7

_FEEDBACK_MAP: dict[ImpairmentType, dict[ErrorType, tuple[str, str]]] = {
    ImpairmentType.RHOTACISM: {
        ErrorType.W_SUBSTITUTION: (
            "Your /r/ sounds like /w/ — lips are rounding.",
            "Square your lips and press the sides of your tongue against your upper back teeth.",
        ),
        ErrorType.L_SUBSTITUTION: (
            "Your /r/ sounds like /l/ — tongue is touching the palate.",
            "Don't let your tongue tip touch the roof of your mouth. Curl it back without contact.",
        ),
        ErrorType.PARTIAL: (
            "Your /r/ is distorted but nearly there.",
            "Sustain the tongue curl a little longer through the vowel that follows.",
        ),
    },
    ImpairmentType.SIGMATISM: {
        ErrorType.DENTAL_LISP: (
            "Your /s/ sounds like a lisp — tongue is too far forward.",
            "Pull your tongue tip just behind your upper teeth, not touching them. "
            "Channel air down the centre.",
        ),
        ErrorType.PARTIAL: (
            "Your /s/ is slightly distorted.",
            "Focus on directing airflow along the centre groove of your tongue.",
        ),
    },
    ImpairmentType.LAMBDACISM: {
        ErrorType.W_SUBSTITUTION: (
            "Your /l/ sounds like /w/.",
            "Place the tip of your tongue firmly against the ridge just behind your upper front teeth.",
        ),
        ErrorType.PARTIAL: (
            "Your /l/ is slightly off.",
            "Make sure the tongue tip touches the alveolar ridge clearly before releasing.",
        ),
    },
}


def analyze_speech(
    audio: AudioInput,
    aligner: dict,
    whisper_model,
) -> SpeechReport:
    """
    Analyse free speech for articulation impairments.

    Steps:
      1. Transcribe with Whisper (text only — no word verification).
      2. Find all target phoneme segments via MMS greedy CTC decode.
      3. Measure acoustic features per phoneme (F3 for /r/; COG for /s/, /z/; F3 for /l/).
      4. Classify each segment.
      5. Aggregate per-impairment scores.
      6. Generate prioritised feedback.
    """
    # 1. Transcription
    wh_result  = whisper_model.transcribe(audio.array, language="en", fp16=False)
    transcript = wh_result.get("text", "").strip()

    # 2. Phoneme segmentation
    all_segments   = find_all_phoneme_segments(audio, aligner)
    target_segments = [s for s in all_segments if s.phoneme in _PHONEME_DOMAIN]

    # 3 & 4. Acoustic analysis + classification
    phoneme_results: list[PhonemeResult] = []

    for seg in target_segments:
        impairment = _PHONEME_DOMAIN[seg.phoneme]
        try:
            if seg.phoneme == "r":
                m   = extract_formants(audio, seg)
                cls = classify(m)
                metric = m.f3
            elif seg.phoneme in ("s", "z"):
                cog = extract_sibilant_cog(audio, seg)
                cls = classify_sibilant(cog)
                metric = cog
            elif seg.phoneme == "l":
                m   = extract_formants(audio, seg)
                cls = _classify_lateral(m)
                metric = m.f2
            else:
                continue
        except ValueError:
            continue  # skip segments where acoustic extraction fails

        phoneme_results.append(PhonemeResult(
            phoneme=seg.phoneme,
            segment=seg,
            impairment_type=impairment,
            error_type=cls.error_type,
            score=cls.rhoticity_score,
            confidence=cls.confidence,
            raw_metric=metric,
        ))

    # 5. Aggregate
    impairment_scores = _aggregate(phoneme_results)
    primary_concern   = _primary_concern(impairment_scores)

    # 6. Feedback
    feedback = _build_feedback(phoneme_results, impairment_scores)

    return SpeechReport(
        transcript=transcript,
        duration=round(len(audio.array) / audio.sample_rate, 3),
        phoneme_results=phoneme_results,
        impairment_scores=impairment_scores,
        primary_concern=primary_concern,
        feedback=feedback,
    )


# ── Internal helpers ──────────────────────────────────────────────────────────

def _classify_lateral(m) -> object:
    """
    Simple /l/ quality check based on F2.
    Normal /l/: F2 ~900–1100 Hz.  /w/ substitution: F2 < 700 Hz.
    """
    from .models import ClassificationResult
    from .classifier import CONFIDENCE_HIGH, CONFIDENCE_LOW

    if m.f2 >= 900.0:
        return ClassificationResult(
            error_type=ErrorType.CORRECT, rhoticity_score=1.0,
            f3_hz=m.f3, confidence=CONFIDENCE_HIGH,
        )
    if m.f2 >= 700.0:
        ratio = (m.f2 - 700.0) / 200.0
        return ClassificationResult(
            error_type=ErrorType.PARTIAL, rhoticity_score=round(ratio * 0.7, 3),
            f3_hz=m.f3, confidence=CONFIDENCE_LOW,
        )
    return ClassificationResult(
        error_type=ErrorType.W_SUBSTITUTION, rhoticity_score=0.0,
        f3_hz=m.f3, confidence=CONFIDENCE_HIGH,
    )


def _aggregate(results: list[PhonemeResult]) -> dict[str, float]:
    buckets: dict[str, list[float]] = defaultdict(list)
    for r in results:
        buckets[r.impairment_type.value].append(r.score)
    return {k: round(sum(v) / len(v), 3) for k, v in buckets.items()}


def _primary_concern(scores: dict[str, float]) -> ImpairmentType | None:
    below = {k: v for k, v in scores.items() if v < _CONCERN_THRESHOLD}
    if not below:
        return None
    return ImpairmentType(min(below, key=below.__getitem__))


def _build_feedback(
    results: list[PhonemeResult],
    scores: dict[str, float],
) -> list[str]:
    if not results:
        return ["No target phonemes detected. Try speaking more clearly or closer to the microphone."]

    lines: list[str] = []

    for imp_str, score in sorted(scores.items(), key=lambda x: x[1]):
        if score >= _CONCERN_THRESHOLD:
            continue

        imp      = ImpairmentType(imp_str)
        relevant = [r for r in results if r.impairment_type == imp]
        errors   = [r.error_type for r in relevant if r.error_type not in (ErrorType.CORRECT, ErrorType.UNCLEAR)]

        if not errors:
            continue

        most_common = max(set(errors), key=errors.count)
        fb_entry    = _FEEDBACK_MAP.get(imp, {}).get(most_common)

        if fb_entry:
            phonemes = sorted({r.phoneme for r in relevant})
            msg, cue = fb_entry
            lines.append(
                f"[{imp.value.title()}] /{'/'.join(phonemes)}/ "
                f"({len(relevant)} instance(s), score {score:.2f}): "
                f"{msg} — {cue}"
            )

    return lines if lines else ["All detected phonemes sound natural. Keep it up!"]
