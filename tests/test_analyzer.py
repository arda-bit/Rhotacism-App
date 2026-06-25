"""
Tests for the free-speech analyzer.  All ML models are mocked.
The aligner mock produces specific phoneme segments; Whisper mock returns
a fixed transcript.  This lets us verify the orchestration logic in isolation.
"""

import numpy as np
import pytest
from unittest.mock import MagicMock

from rhotacism.analyzer import analyze_speech
from rhotacism.models import (
    AudioInput, SpeechReport, ImpairmentType, ErrorType,
)
from tests.conftest import make_mock_aligner_multi, NUM_SAMPLES


SR = 16000
# A 2-second voiced (sawtooth) audio so acoustic stages can extract real features
def make_voiced_audio(duration: float = 2.0) -> AudioInput:
    sr = 16000
    t  = np.arange(int(duration * sr)) / sr
    sig = ((t * 150) % 1.0 - 0.5).astype(np.float32)
    return AudioInput(array=sig, sample_rate=sr)


def make_whisper_mock(text: str = "the red rabbit runs fast") -> MagicMock:
    model = MagicMock()
    model.transcribe.return_value = {
        "text": text,
        "segments": [{"no_speech_prob": 0.05}],
        "language": "en",
    }
    return model


class TestAnalyzeSpeech:
    def test_returns_speech_report(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert isinstance(result, SpeechReport)

    def test_transcript_populated_from_whisper(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock("hello world"))
        assert result.transcript == "hello world"

    def test_duration_matches_audio_length(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio(duration=2.0)
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert abs(result.duration - 2.0) < 0.01

    def test_no_segments_gives_empty_phoneme_results(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert result.phoneme_results == []

    def test_no_segments_gives_empty_impairment_scores(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert result.impairment_scores == {}

    def test_no_segments_primary_concern_is_none(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert result.primary_concern is None

    def test_r_segments_produce_rhotacism_results(self):
        # Place /r/ at frames 50–80 within 2s audio (NUM_FRAMES=200 → frame=0.01s)
        aligner, _ = make_mock_aligner_multi({"r": list(range(50, 81))})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        imp_types = {r.impairment_type for r in result.phoneme_results}
        assert ImpairmentType.RHOTACISM in imp_types

    def test_s_segments_produce_sigmatism_results(self):
        aligner, _ = make_mock_aligner_multi({"s": list(range(50, 81))})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        imp_types = {r.impairment_type for r in result.phoneme_results}
        assert ImpairmentType.SIGMATISM in imp_types

    def test_impairment_scores_keys_match_found_phonemes(self):
        aligner, _ = make_mock_aligner_multi({
            "r": list(range(20, 51)),
            "s": list(range(80, 111)),
        })
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert set(result.impairment_scores.keys()).issubset(
            {ImpairmentType.RHOTACISM.value, ImpairmentType.SIGMATISM.value,
             ImpairmentType.LAMBDACISM.value}
        )

    def test_all_scores_between_0_and_1(self):
        aligner, _ = make_mock_aligner_multi({"r": list(range(50, 81))})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        for score in result.impairment_scores.values():
            assert 0.0 <= score <= 1.0

    def test_feedback_is_non_empty_list(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert isinstance(result.feedback, list)
        assert len(result.feedback) >= 1

    def test_no_findings_returns_positive_feedback(self):
        aligner, _ = make_mock_aligner_multi({})
        audio  = make_voiced_audio()
        result = analyze_speech(audio, aligner, make_whisper_mock())
        assert any("no target" in f.lower() or "natural" in f.lower() or "clearly" in f.lower()
                   for f in result.feedback)
