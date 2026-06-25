import pytest

from rhotacism.classifier import classify
from rhotacism.models import ErrorType
from tests.conftest import (
    make_rhotic_measurement,
    make_w_sub_measurement,
    make_l_sub_measurement,
    make_partial_measurement,
)


class TestClassify:
    def test_low_f3_returns_correct(self):
        result = classify(make_rhotic_measurement())
        assert result.error_type == ErrorType.CORRECT

    def test_high_f3_rising_f2_returns_w_substitution(self):
        result = classify(make_w_sub_measurement())
        assert result.error_type == ErrorType.W_SUBSTITUTION

    def test_high_f3_flat_f2_returns_l_substitution(self):
        result = classify(make_l_sub_measurement())
        assert result.error_type == ErrorType.L_SUBSTITUTION

    def test_transition_zone_returns_partial(self):
        result = classify(make_partial_measurement())
        assert result.error_type == ErrorType.PARTIAL

    def test_score_always_between_0_and_1(self):
        for m in [
            make_rhotic_measurement(),
            make_w_sub_measurement(),
            make_l_sub_measurement(),
            make_partial_measurement(),
        ]:
            result = classify(m)
            assert 0.0 <= result.rhoticity_score <= 1.0

    def test_correct_score_is_1(self):
        result = classify(make_rhotic_measurement())
        assert result.rhoticity_score == 1.0

    def test_w_substitution_score_below_0_3(self):
        result = classify(make_w_sub_measurement())
        assert result.rhoticity_score < 0.3

    def test_partial_score_between_0_3_and_0_7(self):
        result = classify(make_partial_measurement())
        assert 0.3 <= result.rhoticity_score <= 0.7

    def test_confidence_high_for_clear_correct(self):
        result = classify(make_rhotic_measurement())
        assert result.confidence >= 0.8

    def test_confidence_lower_in_transition_zone(self):
        correct = classify(make_rhotic_measurement())
        partial = classify(make_partial_measurement())
        assert partial.confidence < correct.confidence
