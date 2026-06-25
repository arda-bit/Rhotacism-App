from .models import FormantMeasurement, ClassificationResult, ErrorType

# ── Rhotacism thresholds (F3) ─────────────────────────────────────────────────
F3_RHOTIC_MAX   = 2100.0  # Hz — below this is clearly rhotic
F3_PARTIAL_MAX  = 2300.0  # Hz — transition zone
F2_SLOPE_W_MIN  =   80.0  # Hz — rising F2 slope above this → /w/-like

# ── Sigmatism thresholds (spectral COG) ──────────────────────────────────────
SIBILANT_NORMAL_COG  = 4500.0  # Hz — healthy /s/
SIBILANT_PARTIAL_COG = 3500.0  # Hz — transition zone

CONFIDENCE_HIGH = 0.9
CONFIDENCE_LOW  = 0.6


def classify(measurement: FormantMeasurement) -> ClassificationResult:
    """Classify an /r/ segment by F3 and F2 slope → rhotacism diagnosis."""
    f3 = measurement.f3

    if f3 < F3_RHOTIC_MAX:
        return ClassificationResult(
            error_type=ErrorType.CORRECT,
            rhoticity_score=1.0,
            f3_hz=f3,
            confidence=CONFIDENCE_HIGH,
        )

    if f3 < F3_PARTIAL_MAX:
        ratio = (f3 - F3_RHOTIC_MAX) / (F3_PARTIAL_MAX - F3_RHOTIC_MAX)
        score = 0.7 - ratio * 0.4
        return ClassificationResult(
            error_type=ErrorType.PARTIAL,
            rhoticity_score=round(score, 3),
            f3_hz=f3,
            confidence=CONFIDENCE_LOW,
        )

    error = ErrorType.W_SUBSTITUTION if measurement.f2_slope > F2_SLOPE_W_MIN else ErrorType.L_SUBSTITUTION
    score = max(0.0, 0.2 - (f3 - F3_PARTIAL_MAX) / 3500.0)
    return ClassificationResult(
        error_type=error,
        rhoticity_score=round(score, 3),
        f3_hz=f3,
        confidence=CONFIDENCE_HIGH,
    )


def classify_sibilant(cog: float) -> ClassificationResult:
    """
    Classify a /s/ or /z/ segment by spectral centre of gravity → sigmatism diagnosis.

    Normal:      COG ≥ 4500 Hz  → CORRECT
    Transition:  3500–4500 Hz   → PARTIAL
    Dental lisp: COG < 3500 Hz  → DENTAL_LISP
    """
    if cog >= SIBILANT_NORMAL_COG:
        return ClassificationResult(
            error_type=ErrorType.CORRECT,
            rhoticity_score=1.0,
            f3_hz=cog,
            confidence=CONFIDENCE_HIGH,
        )

    if cog >= SIBILANT_PARTIAL_COG:
        ratio = (cog - SIBILANT_PARTIAL_COG) / (SIBILANT_NORMAL_COG - SIBILANT_PARTIAL_COG)
        score = ratio * 0.7
        return ClassificationResult(
            error_type=ErrorType.PARTIAL,
            rhoticity_score=round(score, 3),
            f3_hz=cog,
            confidence=CONFIDENCE_LOW,
        )

    score = max(0.0, cog / SIBILANT_PARTIAL_COG * 0.2)
    return ClassificationResult(
        error_type=ErrorType.DENTAL_LISP,
        rhoticity_score=round(score, 3),
        f3_hz=cog,
        confidence=CONFIDENCE_HIGH,
    )
