import numpy as np
import pytest

from rhotacism.audio import load_audio, validate_audio, preprocess, SAMPLE_RATE
from rhotacism.models import AudioInput
from tests.conftest import make_audio_input, make_wav_bytes, make_stereo_wav_bytes


class TestLoadAudio:
    def test_wav_returns_correct_sample_rate(self):
        result = load_audio(make_wav_bytes(), fmt="wav")
        assert result.sample_rate == SAMPLE_RATE

    def test_wav_returns_float32(self):
        result = load_audio(make_wav_bytes(), fmt="wav")
        assert result.array.dtype == np.float32

    def test_amplitude_normalised_to_unit_range(self):
        result = load_audio(make_wav_bytes(), fmt="wav")
        assert result.array.max() <= 1.0
        assert result.array.min() >= -1.0

    def test_stereo_converted_to_mono(self):
        result = load_audio(make_stereo_wav_bytes(), fmt="wav")
        assert result.array.ndim == 1

    def test_returns_audio_input_instance(self):
        result = load_audio(make_wav_bytes(), fmt="wav")
        assert isinstance(result, AudioInput)

    def test_output_length_matches_duration(self):
        duration = 2.0
        result = load_audio(make_wav_bytes(duration=duration), fmt="wav")
        expected_samples = int(duration * SAMPLE_RATE)
        # Allow ±50 samples for rounding at format boundaries
        assert abs(len(result.array) - expected_samples) <= 50


class TestValidateAudio:
    def test_valid_audio_passes_without_error(self):
        audio = make_audio_input(duration=2.0)
        validate_audio(audio)  # must not raise

    def test_too_short_raises_value_error(self):
        audio = make_audio_input(duration=0.1)
        with pytest.raises(ValueError, match="too short"):
            validate_audio(audio)

    def test_too_long_raises_value_error(self):
        audio = make_audio_input(duration=15.0)
        with pytest.raises(ValueError, match="too long"):
            validate_audio(audio)

    def test_wrong_sample_rate_raises_value_error(self):
        audio = AudioInput(array=np.zeros(8000, dtype=np.float32), sample_rate=8000)
        with pytest.raises(ValueError, match="sample rate"):
            validate_audio(audio)

    def test_exactly_min_duration_passes(self):
        audio = make_audio_input(duration=0.5)
        validate_audio(audio)  # must not raise

    def test_exactly_max_duration_passes(self):
        audio = make_audio_input(duration=10.0)
        validate_audio(audio)  # must not raise


class TestPreprocess:
    def test_returns_audio_input_instance(self):
        result = preprocess(make_audio_input(duration=2.0))
        assert isinstance(result, AudioInput)

    def test_sample_rate_preserved(self):
        audio = make_audio_input(duration=2.0)
        result = preprocess(audio)
        assert result.sample_rate == audio.sample_rate

    def test_output_shorter_or_equal_to_input(self):
        audio = make_audio_input(duration=3.0)
        result = preprocess(audio)
        assert len(result.array) <= len(audio.array)

    def test_output_is_float32(self):
        result = preprocess(make_audio_input(duration=2.0))
        assert result.array.dtype == np.float32

    def test_silent_input_does_not_crash(self):
        silence = AudioInput(array=np.zeros(16000 * 2, dtype=np.float32), sample_rate=SAMPLE_RATE)
        result = preprocess(silence)
        assert isinstance(result, AudioInput)
