import math
import numpy as np
import parselmouth

from .models import AudioInput, PhonemeSegment, FormantMeasurement

MIN_SEGMENT_DURATION = 0.03   # seconds (30 ms)
MAX_FORMANTS         = 5
MAX_FREQUENCY        = 5500.0  # Hz — adult vocal tract ceiling
PRE_EMPHASIS_FROM    = 50.0    # Hz
DEFAULT_WINDOW       = 0.025   # seconds (Praat default)

# Fractional positions within the segment to sample formant values
SAMPLE_FRACTIONS = [0.25, 0.50, 0.75]


def extract_formants(
    audio: AudioInput,
    segment: PhonemeSegment,
) -> FormantMeasurement:
    """
    Extract F1, F2, F3 from the aligned /r/ segment using Praat (parselmouth).

    Samples formants at 25%, 50%, and 75% of the segment and returns the
    mean of whichever time points yield non-NaN values.  Raises ValueError
    if the segment is too short or if no reliable formant values can be
    extracted at any sample point.
    """
    duration       = segment.end_time - segment.start_time
    audio_duration = len(audio.array) / audio.sample_rate

    if duration < MIN_SEGMENT_DURATION:
        raise ValueError(
            f"Segment too short: {duration * 1000:.1f} ms "
            f"(minimum {MIN_SEGMENT_DURATION * 1000:.0f} ms)"
        )
    if segment.end_time > audio_duration:
        raise ValueError(
            f"Segment end ({segment.end_time:.3f}s) exceeds audio duration "
            f"({audio_duration:.3f}s)"
        )

    start_sample = int(segment.start_time * audio.sample_rate)
    end_sample   = int(segment.end_time   * audio.sample_rate)
    seg_array    = audio.array[start_sample:end_sample].astype(np.float64)

    if len(seg_array) == 0:
        raise ValueError("Segment slice produced an empty array — check segment times")

    snd = parselmouth.Sound(seg_array, sampling_frequency=float(audio.sample_rate))

    # Shrink window for very short segments so Praat can fit it inside the signal
    window_length = min(DEFAULT_WINDOW, duration / 3.0)

    formant = snd.to_formant_burg(
        max_number_of_formants=MAX_FORMANTS,
        maximum_formant=MAX_FREQUENCY,
        window_length=window_length,
        pre_emphasis_from=PRE_EMPHASIS_FROM,
    )

    sample_times = [duration * frac for frac in SAMPLE_FRACTIONS]

    f1_vals = [formant.get_value_at_time(1, t) for t in sample_times]
    f2_vals = [formant.get_value_at_time(2, t) for t in sample_times]
    f3_vals = [formant.get_value_at_time(3, t) for t in sample_times]

    f1 = _safe_mean(f1_vals)
    f2 = _safe_mean(f2_vals)
    f3 = _safe_mean(f3_vals)

    if any(math.isnan(v) for v in [f1, f2, f3]):
        raise ValueError(
            "Could not extract reliable formants — signal may be too noisy or too short"
        )

    # F2 slope: F2(75%) − F2(25%); positive = rising (w-like coarticulation)
    f2_at_25 = f2_vals[0]
    f2_at_75 = f2_vals[2]
    if not math.isnan(f2_at_25) and not math.isnan(f2_at_75):
        f2_slope = f2_at_75 - f2_at_25
    else:
        f2_slope = 0.0

    return FormantMeasurement(
        f1=round(f1, 1),
        f2=round(f2, 1),
        f3=round(f3, 1),
        f2_slope=round(f2_slope, 1),
        duration=round(duration, 4),
    )


def _safe_mean(values: list[float]) -> float:
    valid = [v for v in values if not math.isnan(v)]
    return float(np.mean(valid)) if valid else float("nan")
