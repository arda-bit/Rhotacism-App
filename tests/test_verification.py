import numpy as np
import pytest
from unittest.mock import MagicMock

from rhotacism.verification import verify_word, _normalise, _edit_distance
from rhotacism.models import AudioInput

DUMMY_AUDIO = AudioInput(array=np.zeros(16000 * 2, dtype=np.float32), sample_rate=16000)


def make_mock_model(text: str, no_speech_prob: float = 0.05):
    """Return a mock Whisper model whose transcribe() returns controlled output."""
    model = MagicMock()
    model.transcribe.return_value = {
        "text": text,
        "segments": [{"no_speech_prob": no_speech_prob}],
        "language": "en",
    }
    return model


def make_silent_model():
    """Simulate Whisper finding no speech segments."""
    model = MagicMock()
    model.transcribe.return_value = {"text": "", "segments": [], "language": "en"}
    return model


class TestVerifyWord:
    def test_correct_word_returns_verified_true(self):
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" red"))
        assert result.verified is True

    def test_wrong_word_returns_verified_false(self):
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" blue sky"))
        assert result.verified is False

    def test_match_is_case_insensitive(self):
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" Red."))
        assert result.verified is True

    def test_punctuation_stripped_before_match(self):
        result = verify_word(DUMMY_AUDIO, "rabbit", make_mock_model(" rabbit!"))
        assert result.verified is True

    def test_fuzzy_match_one_edit_away(self):
        # "wed" is edit-distance 1 from "red" — valid near-miss for rhotacism
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" wed"))
        assert result.verified is True

    def test_fuzzy_match_beyond_distance_rejected(self):
        # "blue" is distance 3 from "red" — should not match
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" blue"))
        assert result.verified is False

    def test_target_word_found_within_sentence(self):
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" the red ball"))
        assert result.verified is True

    def test_empty_transcription_returns_false(self):
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(""))
        assert result.verified is False

    def test_no_segments_returns_unverified_with_zero_confidence(self):
        result = verify_word(DUMMY_AUDIO, "red", make_silent_model())
        assert result.verified is False
        assert result.confidence == 0.0

    def test_transcription_string_always_populated(self):
        result = verify_word(DUMMY_AUDIO, "red", make_mock_model(" red"))
        assert isinstance(result.transcription, str)

    def test_high_no_speech_prob_lowers_confidence(self):
        low_conf  = verify_word(DUMMY_AUDIO, "red", make_mock_model(" red", no_speech_prob=0.8))
        high_conf = verify_word(DUMMY_AUDIO, "red", make_mock_model(" red", no_speech_prob=0.05))
        assert low_conf.confidence < high_conf.confidence

    def test_fuzzy_match_confidence_discounted(self):
        exact = verify_word(DUMMY_AUDIO, "red", make_mock_model(" red",  no_speech_prob=0.05))
        fuzzy = verify_word(DUMMY_AUDIO, "red", make_mock_model(" wed",  no_speech_prob=0.05))
        assert fuzzy.confidence < exact.confidence


class TestHelpers:
    def test_normalise_lowercases(self):
        assert _normalise("Red") == "red"

    def test_normalise_strips_punctuation(self):
        assert _normalise("rabbit!") == "rabbit"

    def test_normalise_empty_string(self):
        assert _normalise("") == ""

    def test_edit_distance_identical(self):
        assert _edit_distance("red", "red") == 0

    def test_edit_distance_one_substitution(self):
        assert _edit_distance("red", "wed") == 1

    def test_edit_distance_one_insertion(self):
        assert _edit_distance("red", "reed") == 1

    def test_edit_distance_one_deletion(self):
        assert _edit_distance("red", "rd") == 1

    def test_edit_distance_symmetric(self):
        assert _edit_distance("abc", "xyz") == _edit_distance("xyz", "abc")
