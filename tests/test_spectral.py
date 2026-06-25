import numpy as np
import pytest

from rhotacism.spectral import extract_sibilant_cog, SIBILANT_NORMAL_COG_HZ, SIBILANT_PARTIAL_COG_HZ
from rhotacism.classifier import classify_sibilant
from rhotacism.models import AudioInput, PhonemeSegment, ErrorType

SR = 16000


def make_high_freq_audio(freq: float = 6000.0, duration: float = 0.2) -> AudioInput:
    """Sine at freq Hz — approximates a high-COG sibilant."""
    t   = np.arange(int(duration * SR)) / SR
    sig = np.sin(2 * np.pi * freq * t).astype(np.float32)
    return AudioInput(array=sig, sample_rate=SR)


def make_low_freq_audio(freq: float = 1500.0, duration: float = 0.2) -> AudioInput:
    """Sine at freq Hz — approximates a low-COG lisped sibilant."""
    t   = np.arange(int(duration * SR)) / SR
    sig = np.sin(2 * np.pi * freq * t).astype(np.float32)
    return AudioInput(array=sig, sample_rate=SR)


def make_segment(start: float = 0.05, end: float = 0.15) -> PhonemeSegment:
    return PhonemeSegment(phoneme="s", start_time=start, end_time=end)


class TestExtractSibilantCog:
    def test_returns_positive_float(self):
        cog = extract_sibilant_cog(make_high_freq_audio(), make_segment())
        assert isinstance(cog, float)
        assert cog > 0.0

    def test_high_freq_signal_has_high_cog(self):
        cog = extract_sibilant_cog(make_high_freq_audio(freq=6000.0), make_segment())
        # Pure 6kHz sine: COG ≈ 6000 Hz — well above normal sibilant threshold
        assert cog > SIBILANT_PARTIAL_COG_HZ

    def test_low_freq_signal_has_low_cog(self):
        cog = extract_sibilant_cog(make_low_freq_audio(freq=1500.0), make_segment())
        # Pure 1.5kHz sine: COG ≈ 1500 Hz — below lisp threshold
        assert cog < SIBILANT_NORMAL_COG_HZ

    def test_cog_tracks_signal_frequency(self):
        cog_high = extract_sibilant_cog(make_high_freq_audio(freq=6000.0), make_segment())
        cog_low  = extract_sibilant_cog(make_low_freq_audio(freq=1500.0),  make_segment())
        assert cog_high > cog_low

    def test_segment_too_short_raises_value_error(self):
        seg = PhonemeSegment(phoneme="s", start_time=0.05, end_time=0.06)  # 10 ms
        with pytest.raises(ValueError, match="too short"):
            extract_sibilant_cog(make_high_freq_audio(), seg)

    def test_segment_out_of_bounds_raises_value_error(self):
        audio = make_high_freq_audio(duration=0.1)
        seg   = PhonemeSegment(phoneme="s", start_time=0.08, end_time=0.15)
        with pytest.raises(ValueError, match="exceeds audio duration"):
            extract_sibilant_cog(audio, seg)

    def test_cog_in_physically_plausible_range(self):
        cog = extract_sibilant_cog(make_high_freq_audio(), make_segment())
        assert 100.0 < cog < 8001.0  # Nyquist = 8000 Hz for 16kHz audio


class TestClassifySibilant:
    def test_high_cog_returns_correct(self):
        result = classify_sibilant(5000.0)
        assert result.error_type == ErrorType.CORRECT

    def test_high_cog_score_is_1(self):
        result = classify_sibilant(5000.0)
        assert result.rhoticity_score == 1.0

    def test_low_cog_returns_dental_lisp(self):
        result = classify_sibilant(2000.0)
        assert result.error_type == ErrorType.DENTAL_LISP

    def test_mid_cog_returns_partial(self):
        result = classify_sibilant(4000.0)
        assert result.error_type == ErrorType.PARTIAL

    def test_partial_score_between_0_and_0_7(self):
        result = classify_sibilant(4000.0)
        assert 0.0 <= result.rhoticity_score <= 0.7

    def test_dental_lisp_score_below_0_3(self):
        result = classify_sibilant(2000.0)
        assert result.rhoticity_score < 0.3

    def test_score_always_between_0_and_1(self):
        for cog in [1000.0, 2500.0, 3500.0, 4000.0, 5000.0, 6000.0]:
            result = classify_sibilant(cog)
            assert 0.0 <= result.rhoticity_score <= 1.0

    def test_confidence_high_outside_transition_zone(self):
        correct = classify_sibilant(5500.0)
        lisp    = classify_sibilant(2000.0)
        assert correct.confidence >= 0.8
        assert lisp.confidence    >= 0.8

    def test_confidence_lower_in_transition_zone(self):
        correct  = classify_sibilant(5500.0)
        partial  = classify_sibilant(4000.0)
        assert partial.confidence < correct.confidence
