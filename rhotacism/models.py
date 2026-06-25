from dataclasses import dataclass, field
from enum import Enum
import numpy as np


class ErrorType(str, Enum):
    CORRECT        = "correct"
    W_SUBSTITUTION = "w_substitution"
    L_SUBSTITUTION = "l_substitution"
    DENTAL_LISP    = "dental_lisp"    # /s/ or /z/ with tongue too far forward
    PARTIAL        = "partial"
    UNCLEAR        = "unclear"


class ImpairmentType(str, Enum):
    RHOTACISM  = "rhotacism"   # /r/ difficulties
    SIGMATISM  = "sigmatism"   # /s/, /z/ difficulties (lisping)
    LAMBDACISM = "lambdacism"  # /l/ difficulties


@dataclass
class AudioInput:
    array: np.ndarray  # float32, mono, 16 kHz
    sample_rate: int


@dataclass
class VerificationResult:
    verified:      bool
    transcription: str
    confidence:    float


@dataclass
class PhonemeSegment:
    phoneme:    str
    start_time: float  # seconds
    end_time:   float  # seconds


@dataclass
class FormantMeasurement:
    f1:       float  # Hz
    f2:       float  # Hz
    f3:       float  # Hz
    f2_slope: float  # Hz — positive = rising, negative = falling
    duration: float  # seconds


@dataclass
class ClassificationResult:
    error_type:      ErrorType
    rhoticity_score: float  # 0.0 → 1.0
    f3_hz:           float
    confidence:      float


@dataclass
class FeedbackResult:
    message:  str
    cue:      str
    score:    float
    level_up: bool


@dataclass
class PhonemeResult:
    """Acoustic analysis result for a single detected phoneme occurrence."""
    phoneme:         str
    segment:         PhonemeSegment
    impairment_type: ImpairmentType
    error_type:      ErrorType
    score:           float   # 0.0 = impaired → 1.0 = normal
    confidence:      float
    raw_metric:      float   # F3 Hz for rhotacism; spectral COG Hz for sigmatism


@dataclass
class SpeechReport:
    """Full impairment analysis of a free-speech utterance."""
    transcript:        str
    duration:          float
    phoneme_results:   list[PhonemeResult]
    impairment_scores: dict[str, float]        # ImpairmentType.value → mean score
    primary_concern:   ImpairmentType | None   # highest-severity impairment, or None
    feedback:          list[str]
