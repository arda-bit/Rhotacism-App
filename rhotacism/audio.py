import io
import numpy as np
from pydub import AudioSegment
import noisereduce as nr
import librosa

from .models import AudioInput

SAMPLE_RATE = 16000
MIN_DURATION = 0.5   # seconds
MAX_DURATION = 10.0  # seconds
NOISE_PROP_DECREASE = 0.8
SILENCE_TOP_DB = 25


def load_audio(file_bytes: bytes, fmt: str | None = None) -> AudioInput:
    """Convert any audio format (m4a, wav, webm, mp3) to 16 kHz mono float32."""
    segment = AudioSegment.from_file(io.BytesIO(file_bytes), format=fmt)
    segment = segment.set_frame_rate(SAMPLE_RATE).set_channels(1)
    samples = np.array(segment.get_array_of_samples()).astype(np.float32) / 32768.0
    return AudioInput(array=samples, sample_rate=SAMPLE_RATE)


def validate_audio(audio: AudioInput) -> None:
    """Raise ValueError if the audio fails any pre-flight check."""
    if audio.sample_rate != SAMPLE_RATE:
        raise ValueError(
            f"Expected sample rate {SAMPLE_RATE}, got {audio.sample_rate}"
        )
    duration = len(audio.array) / audio.sample_rate
    if duration < MIN_DURATION:
        raise ValueError(
            f"Audio too short: {duration:.2f}s (minimum {MIN_DURATION}s)"
        )
    if duration > MAX_DURATION:
        raise ValueError(
            f"Audio too long: {duration:.2f}s (maximum {MAX_DURATION}s)"
        )


def preprocess(audio: AudioInput) -> AudioInput:
    """Apply noise reduction and trim leading/trailing silence."""
    reduced = nr.reduce_noise(
        y=audio.array,
        sr=audio.sample_rate,
        stationary=True,
        prop_decrease=NOISE_PROP_DECREASE,
    )
    trimmed, _ = librosa.effects.trim(reduced, top_db=SILENCE_TOP_DB)
    return AudioInput(array=trimmed, sample_rate=audio.sample_rate)
