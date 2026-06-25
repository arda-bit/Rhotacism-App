import pytest

from rhotacism.feedback import generate_feedback
from rhotacism.models import ClassificationResult, ErrorType


def make_result(error_type: ErrorType, score: float = 0.5) -> ClassificationResult:
    return ClassificationResult(
        error_type=error_type,
        rhoticity_score=score,
        f3_hz=2000.0,
        confidence=0.9,
    )


class TestGenerateFeedback:
    def test_correct_result_positive_message(self):
        result = generate_feedback(make_result(ErrorType.CORRECT, 1.0), "red", [])
        assert "red" in result.message.lower() or "r" in result.message.lower()

    def test_w_substitution_lip_cue_in_output(self):
        result = generate_feedback(make_result(ErrorType.W_SUBSTITUTION, 0.1), "red", [])
        assert "lip" in result.cue.lower() or "tongue" in result.cue.lower()

    def test_l_substitution_tongue_cue_in_output(self):
        result = generate_feedback(make_result(ErrorType.L_SUBSTITUTION, 0.1), "red", [])
        assert "tongue" in result.cue.lower()

    def test_partial_sustain_cue_in_output(self):
        result = generate_feedback(make_result(ErrorType.PARTIAL, 0.5), "red", [])
        assert "sustain" in result.cue.lower() or "hold" in result.message.lower()

    def test_unclear_suggests_quieter_space(self):
        result = generate_feedback(make_result(ErrorType.UNCLEAR, 0.0), "red", [])
        assert "quiet" in result.message.lower() or "unclear" in result.message.lower()

    def test_level_up_after_three_consecutive_high_scores(self):
        result = generate_feedback(make_result(ErrorType.CORRECT, 0.9), "red", [0.85, 0.9])
        assert result.level_up is True

    def test_no_level_up_with_mixed_scores(self):
        result = generate_feedback(make_result(ErrorType.CORRECT, 0.9), "red", [0.5, 0.9])
        assert result.level_up is False

    def test_no_level_up_with_only_two_high_scores(self):
        result = generate_feedback(make_result(ErrorType.CORRECT, 0.9), "red", [0.9])
        assert result.level_up is False

    def test_score_propagated_to_result(self):
        result = generate_feedback(make_result(ErrorType.CORRECT, 0.95), "red", [])
        assert result.score == 0.95

    def test_target_word_appears_in_correct_message(self):
        result = generate_feedback(make_result(ErrorType.CORRECT, 1.0), "rabbit", [])
        assert "rabbit" in result.message
