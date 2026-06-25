import math
import numpy as np
import parselmouth

from .models import AudioInput, PhonemeSegment

# Spectral Centre of Gravity thresholds for English /s/ and /z/
# Reference: Stevens (1998), Jongman et al. (2000)
SIBILANT_NORMAL_COG_HZ  = 4500.0  # Hz — typical for a healthy /s/
SIBILANT_PARTIAL_COG_HZ = 3500.0  # Hz — transition zone
MIN_SEGMENT_DURATION     = 0.03   # seconds


def extract_sibilant_cog(
    audio: AudioInput,
    segment: PhonemeSegment,
) -> float:
    """
    Spectral centre of gravity (COG) of a /s/ or /z/ segment, in Hz.

    Normal /s/: COG > 4500 Hz  (energy concentrated in high frequencies)
    Dental lisp: COG 2000–3500 Hz  (tongue too far forward, low-frequency energy)
    Lateral lisp: similar COG range but distinct spectral shape

    Raises ValueError if the segment is too short, out of bounds, or silent.
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
        raise ValueError("Segment slice produced an empty array")

    snd      = parselmouth.Sound(seg_array, sampling_frequency=float(audio.sample_rate))
    spectrum = snd.to_spectrum()
    cog      = spectrum.get_centre_of_gravity(power=2)

    if math.isnan(cog):
        raise ValueError("Could not extract spectral COG — segment may be silent")

    return float(cog)
