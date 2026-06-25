import io
from unittest.mock import MagicMock
import numpy as np
import torch
import pytest
from pydub import AudioSegment
from rhotacism.models import AudioInput, FormantMeasurement, PhonemeSegment

# Full MMS_FA vocabulary (confirmed from bundle.get_dict())
MOCK_VOCAB = {
    "-": 0, "a": 1, "i": 2, "e": 3, "n": 4,
    "o": 5, "u": 6, "t": 7, "s": 8, "r": 9,
    "m": 10, "k": 11, "l": 12, "d": 13, "g": 14,
    "h": 15, "y": 16, "b": 17, "p": 18, "w": 19,
    "c": 20, "v": 21, "j": 22, "z": 23, "f": 24,
    "'": 25, "q": 26, "x": 27, "*": 28,
}
VOCAB_SIZE  = len(MOCK_VOCAB)   # 29
NUM_FRAMES  = 200
NUM_SAMPLES = 32000             # 2 s at 16 kHz → frame_duration = 0.01 s
R_TOKEN_INDEX = MOCK_VOCAB["r"] # 9


# ── Audio helpers ─────────────────────────────────────────────────────────────

def make_sine(duration: float = 2.0, freq: float = 440.0, sr: int = 16000) -> np.ndarray:
    t = np.arange(int(duration * sr)) / sr
    return np.sin(2 * np.pi * freq * t).astype(np.float32)


def make_audio_input(duration: float = 2.0, sr: int = 16000) -> AudioInput:
    return AudioInput(array=make_sine(duration=duration), sample_rate=sr)


def make_wav_bytes(duration: float = 2.0, sr: int = 16000) -> bytes:
    samples = (make_sine(duration=duration, sr=sr) * 32767).astype(np.int16)
    seg = AudioSegment(samples.tobytes(), frame_rate=sr, sample_width=2, channels=1)
    buf = io.BytesIO()
    seg.export(buf, format="wav")
    return buf.getvalue()


def make_stereo_wav_bytes(duration: float = 1.0, sr: int = 16000) -> bytes:
    mono   = (make_sine(duration=duration, sr=sr) * 32767).astype(np.int16)
    stereo = np.column_stack([mono, mono])
    seg    = AudioSegment(stereo.tobytes(), frame_rate=sr, sample_width=2, channels=2)
    buf    = io.BytesIO()
    seg.export(buf, format="wav")
    return buf.getvalue()


# ── Formant measurement fixtures ──────────────────────────────────────────────

def make_rhotic_measurement() -> FormantMeasurement:
    return FormantMeasurement(f1=500.0, f2=1200.0, f3=1900.0, f2_slope=-10.0, duration=0.08)

def make_w_sub_measurement() -> FormantMeasurement:
    return FormantMeasurement(f1=500.0, f2=900.0,  f3=2700.0, f2_slope=150.0, duration=0.08)

def make_l_sub_measurement() -> FormantMeasurement:
    return FormantMeasurement(f1=400.0, f2=1100.0, f3=2600.0, f2_slope=20.0,  duration=0.08)

def make_partial_measurement() -> FormantMeasurement:
    return FormantMeasurement(f1=480.0, f2=1100.0, f3=2200.0, f2_slope=30.0,  duration=0.08)


# ── Aligner mock helpers ──────────────────────────────────────────────────────

def make_mock_aligner_multi(
    phoneme_frames: dict[str, list[int]],
    num_frames: int = NUM_FRAMES,
) -> tuple[dict, AudioInput]:
    """
    General aligner mock.
    phoneme_frames: {'r': [10,11,12], 's': [50,51,52], ...}
    """
    emission = torch.zeros(1, num_frames, VOCAB_SIZE)
    emission[:, :, 0] = 5.0  # default: '-' token

    for phoneme, frames in phoneme_frames.items():
        idx = MOCK_VOCAB.get(phoneme)
        if idx is None:
            continue
        for f in frames:
            if 0 <= f < num_frames:
                emission[0, f, :]   = 0.0
                emission[0, f, idx] = 10.0

    mock_model = MagicMock()
    mock_model.return_value = (emission, None)

    mock_bundle = MagicMock()
    mock_bundle.get_dict.return_value = MOCK_VOCAB

    audio = AudioInput(
        array=np.zeros(NUM_SAMPLES, dtype=np.float32),
        sample_rate=16000,
    )
    return {"bundle": mock_bundle, "model": mock_model}, audio


def make_mock_aligner(r_frames: list[int]) -> tuple[dict, AudioInput]:
    """Backward-compatible single-phoneme mock (r only)."""
    return make_mock_aligner_multi({"r": r_frames})
