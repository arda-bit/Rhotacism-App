import pytest
from rhotacism.alignment import (
    find_r_segment, find_all_phoneme_segments,
    MIN_SEGMENT_DURATION, MAX_FRAME_GAP,
)
from rhotacism.models import PhonemeSegment
from tests.conftest import make_mock_aligner, make_mock_aligner_multi, NUM_FRAMES, NUM_SAMPLES

# frame_duration = NUM_SAMPLES / (NUM_FRAMES * 16000) = 32000 / 3_200_000 = 0.01 s
FRAME_DURATION = NUM_SAMPLES / (NUM_FRAMES * 16000)

# Minimum frames needed to meet MIN_SEGMENT_DURATION (30 ms at 10 ms/frame = 3 frames)
MIN_FRAMES = int(MIN_SEGMENT_DURATION / FRAME_DURATION)  # = 3


class TestFindRSegment:
    def test_returns_phoneme_segment_when_r_present(self):
        aligner, audio = make_mock_aligner(r_frames=list(range(10, 20)))
        result = find_r_segment(audio, aligner)
        assert isinstance(result, PhonemeSegment)

    def test_returns_none_when_no_r_frames(self):
        aligner, audio = make_mock_aligner(r_frames=[])
        result = find_r_segment(audio, aligner)
        assert result is None

    def test_phoneme_field_is_r(self):
        aligner, audio = make_mock_aligner(r_frames=list(range(10, 20)))
        result = find_r_segment(audio, aligner)
        assert result.phoneme == "r"

    def test_start_time_is_positive(self):
        aligner, audio = make_mock_aligner(r_frames=list(range(10, 20)))
        result = find_r_segment(audio, aligner)
        assert result.start_time > 0.0

    def test_end_time_greater_than_start_time(self):
        aligner, audio = make_mock_aligner(r_frames=list(range(10, 20)))
        result = find_r_segment(audio, aligner)
        assert result.end_time > result.start_time

    def test_segment_meets_minimum_duration(self):
        aligner, audio = make_mock_aligner(r_frames=list(range(10, 20)))
        result = find_r_segment(audio, aligner)
        assert (result.end_time - result.start_time) >= MIN_SEGMENT_DURATION

    def test_cluster_too_short_returns_none(self):
        # MIN_FRAMES - 1 frames → below 30 ms threshold
        short_frames = list(range(10, 10 + MIN_FRAMES - 1))
        aligner, audio = make_mock_aligner(r_frames=short_frames)
        result = find_r_segment(audio, aligner)
        assert result is None

    def test_exactly_min_frames_returns_segment(self):
        exact_frames = list(range(10, 10 + MIN_FRAMES))
        aligner, audio = make_mock_aligner(r_frames=exact_frames)
        result = find_r_segment(audio, aligner)
        assert result is not None

    def test_gap_within_tolerance_stays_one_cluster(self):
        # Frames 10–14, gap of MAX_FRAME_GAP, then frames 17–20
        # The gap should be bridged → one cluster from 10 to 20
        frames = list(range(10, 15)) + list(range(15 + MAX_FRAME_GAP, 21))
        aligner, audio = make_mock_aligner(r_frames=frames)
        result = find_r_segment(audio, aligner)
        assert result is not None
        # Start should correspond to first frame (10)
        assert abs(result.start_time - 10 * FRAME_DURATION) < 1e-6

    def test_two_separate_clusters_returns_first(self):
        # Cluster A: frames 10–15, Cluster B: frames 80–90
        frames = list(range(10, 16)) + list(range(80, 91))
        aligner, audio = make_mock_aligner(r_frames=frames)
        result = find_r_segment(audio, aligner)
        # First cluster ends well before frame 80
        assert result.end_time < 80 * FRAME_DURATION

    def test_start_time_matches_first_r_frame(self):
        first_frame = 25
        aligner, audio = make_mock_aligner(r_frames=list(range(first_frame, first_frame + 5)))
        result = find_r_segment(audio, aligner)
        expected_start = first_frame * FRAME_DURATION
        assert abs(result.start_time - expected_start) < 1e-6

    def test_end_time_matches_last_r_frame_plus_one(self):
        last_frame = 30
        aligner, audio = make_mock_aligner(r_frames=list(range(25, last_frame + 1)))
        result = find_r_segment(audio, aligner)
        expected_end = (last_frame + 1) * FRAME_DURATION
        assert abs(result.end_time - expected_end) < 1e-6


class TestFindAllPhonemeSegments:
    FRAME_DURATION = NUM_SAMPLES / (NUM_FRAMES * 16000)  # 0.01 s

    def test_finds_r_segments(self):
        aligner, audio = make_mock_aligner_multi({"r": list(range(10, 20))})
        segs = find_all_phoneme_segments(audio, aligner)
        assert any(s.phoneme == "r" for s in segs)

    def test_finds_s_segments(self):
        aligner, audio = make_mock_aligner_multi({"s": list(range(50, 60))})
        segs = find_all_phoneme_segments(audio, aligner)
        assert any(s.phoneme == "s" for s in segs)

    def test_finds_both_r_and_s_in_same_audio(self):
        aligner, audio = make_mock_aligner_multi({
            "r": list(range(10, 20)),
            "s": list(range(60, 70)),
        })
        segs = find_all_phoneme_segments(audio, aligner)
        phonemes = {s.phoneme for s in segs}
        assert "r" in phonemes and "s" in phonemes

    def test_results_sorted_by_start_time(self):
        aligner, audio = make_mock_aligner_multi({
            "s": list(range(80, 90)),
            "r": list(range(10, 20)),
        })
        segs = find_all_phoneme_segments(audio, aligner)
        times = [s.start_time for s in segs]
        assert times == sorted(times)

    def test_empty_when_no_target_phonemes_in_audio(self):
        aligner, audio = make_mock_aligner_multi({})
        segs = find_all_phoneme_segments(audio, aligner)
        assert segs == []

    def test_all_segments_meet_min_duration(self):
        aligner, audio = make_mock_aligner_multi({
            "r": list(range(10, 20)),
            "s": list(range(50, 60)),
        })
        for seg in find_all_phoneme_segments(audio, aligner):
            assert (seg.end_time - seg.start_time) >= MIN_SEGMENT_DURATION

    def test_short_cluster_excluded(self):
        # Only 2 frames — 20 ms < MIN_SEGMENT_DURATION 30 ms
        aligner, audio = make_mock_aligner_multi({"r": [10, 11]})
        segs = find_all_phoneme_segments(audio, aligner)
        assert not any(s.phoneme == "r" for s in segs)

    def test_multiple_r_clusters_all_returned(self):
        aligner, audio = make_mock_aligner_multi({
            "r": list(range(10, 15)) + list(range(80, 85)),
        })
        r_segs = [s for s in find_all_phoneme_segments(audio, aligner) if s.phoneme == "r"]
        assert len(r_segs) == 2

    def test_z_segments_detected(self):
        aligner, audio = make_mock_aligner_multi({"z": list(range(30, 45))})
        segs = find_all_phoneme_segments(audio, aligner)
        assert any(s.phoneme == "z" for s in segs)

    def test_l_segments_detected(self):
        aligner, audio = make_mock_aligner_multi({"l": list(range(30, 45))})
        segs = find_all_phoneme_segments(audio, aligner)
        assert any(s.phoneme == "l" for s in segs)
