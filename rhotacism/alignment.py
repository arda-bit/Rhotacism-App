import torch
from .models import AudioInput, PhonemeSegment

MIN_SEGMENT_DURATION = 0.03  # seconds (30 ms)
MAX_FRAME_GAP        = 2     # frames — bridge brief dips within a phoneme cluster

# MMS_FA vocabulary (confirmed): r=9, s=8, l=12, z=23
# These are the phonemes we know how to analyse acoustically.
TARGET_PHONEMES = {"r", "s", "l", "z"}


def load_aligner() -> dict:
    """Download (once) and return the MMS forced-alignment model."""
    import torchaudio
    bundle = torchaudio.pipelines.MMS_FA
    model  = bundle.get_model()
    model.eval()
    return {"bundle": bundle, "model": model}


# ── Public API ────────────────────────────────────────────────────────────────

def find_all_phoneme_segments(
    audio: AudioInput,
    aligner: dict,
) -> list[PhonemeSegment]:
    """
    Run MMS greedy CTC decode and return every target-phoneme segment found,
    sorted by start time.

    This drives the free-speech analysis path.  Each returned segment is at
    least MIN_SEGMENT_DURATION seconds long and maps to one of TARGET_PHONEMES.
    """
    emission, frame_duration = _get_emission(audio, aligner)
    if emission is None:
        return []

    vocab         = aligner["bundle"].get_dict()
    target_vocab  = {vocab[p]: p for p in TARGET_PHONEMES if p in vocab}
    predicted     = torch.argmax(emission[0], dim=-1)

    segments: list[PhonemeSegment] = []

    for token_idx, phoneme in target_vocab.items():
        frame_list = (predicted == token_idx).nonzero(as_tuple=True)[0].tolist()

        for start_f, end_f in _cluster_frames(frame_list, MAX_FRAME_GAP):
            start_time = start_f * frame_duration
            end_time   = (end_f + 1) * frame_duration

            if (end_time - start_time) >= MIN_SEGMENT_DURATION:
                segments.append(PhonemeSegment(
                    phoneme=phoneme,
                    start_time=round(start_time, 4),
                    end_time=round(end_time, 4),
                ))

    return sorted(segments, key=lambda s: s.start_time)


def find_r_segment(
    audio: AudioInput,
    aligner: dict,
) -> PhonemeSegment | None:
    """
    Return the first /r/ segment found.
    Kept for the guided single-word therapy path (Stages 2–4 of the original pipeline).
    """
    r_segments = [s for s in find_all_phoneme_segments(audio, aligner) if s.phoneme == "r"]
    return r_segments[0] if r_segments else None


# ── Internal helpers ──────────────────────────────────────────────────────────

def _get_emission(
    audio: AudioInput,
    aligner: dict,
) -> tuple[torch.Tensor | None, float]:
    """Run the MMS model and return (emission, frame_duration_seconds)."""
    model       = aligner["model"]
    num_samples = audio.array.shape[0]

    if num_samples == 0:
        return None, 0.0

    waveform = torch.tensor(audio.array).unsqueeze(0)

    with torch.inference_mode():
        emission, _ = model(waveform)

    num_frames = emission.size(1)
    if num_frames == 0:
        return None, 0.0

    frame_duration = num_samples / (num_frames * audio.sample_rate)
    return emission, frame_duration


def _cluster_frames(frames: list[int], gap: int) -> list[tuple[int, int]]:
    """
    Group consecutive frame indices into (start, end) pairs.
    Gaps of at most `gap` frames between indices are bridged.
    """
    if not frames:
        return []

    clusters: list[tuple[int, int]] = []
    start = end = frames[0]

    for f in frames[1:]:
        if f - end <= gap:
            end = f
        else:
            clusters.append((start, end))
            start = end = f

    clusters.append((start, end))
    return clusters
