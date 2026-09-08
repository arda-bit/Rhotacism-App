"""
FastAPI server — exposes the speech impairment pipeline over HTTP.

Startup:  uv run uvicorn server:app --host 0.0.0.0 --port 8000
iOS sends multipart/form-data audio uploads; server returns JSON.

Two endpoints:
  POST /analyze       — free speech, any content, full impairment report
  POST /analyze-word  — guided therapy mode, checks a specific target word
  GET  /health        — liveness probe
"""

import asyncio
import json
import threading
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from rhotacism.audio        import load_audio, validate_audio, preprocess
from rhotacism.verification import load_verifier, verify_word
from rhotacism.formants     import extract_formants
from rhotacism.classifier   import classify
from rhotacism.feedback     import generate_feedback
from rhotacism.models       import PhonemeSegment

_executor = ThreadPoolExecutor(max_workers=4)
_state: dict = {}
_models_ready = False


def _load_models():
    global _models_ready
    try:
        print("Loading Whisper model...")
        _state["whisper"] = load_verifier()
        _models_ready = True
        print("All models ready.")
    except Exception as exc:
        print(f"Model loading failed: {exc}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load models in a background thread so the server becomes healthy immediately.
    # Railway's health check will pass while models download; analyze endpoints
    # return 503 until ready.
    threading.Thread(target=_load_models, daemon=True).start()
    yield
    _executor.shutdown(wait=False)


app = FastAPI(title="Speech Impairment API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Endpoints ──────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "models_loaded": _models_ready}


@app.post("/analyze")
async def analyze(audio: UploadFile = File(...)):
    raise HTTPException(status_code=503, detail="Free-speech analysis requires the MMS aligner which is not loaded on this deployment.")


@app.post("/analyze-word")
async def analyze_word(
    audio:          UploadFile  = File(...),
    target_word:    str         = Form(...),
    session_scores: str         = Form("[]"),
):
    if not _models_ready:
        raise HTTPException(status_code=503, detail="Models are still loading, please retry in a moment.")
    """
    Guided therapy endpoint.
    Verifies the user said `target_word`, then analyses the /r/ phoneme quality.
    Returns a FeedbackResult as JSON.
    """
    raw  = await audio.read()
    fmt  = _ext(audio.filename)
    scores: list[float] = json.loads(session_scores)

    try:
        audio_input = load_audio(raw, fmt=fmt)
        validate_audio(audio_input)
        clean       = preprocess(audio_input)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    loop = asyncio.get_running_loop()

    def _run():
        verification = verify_word(clean, target_word, _state["whisper"])
        if not verification.verified:
            return {"verified": False, "transcription": verification.transcription,
                    "message": f"Could not confirm you said '{target_word}'. Please try again.",
                    "cue": "", "score": 0.0, "level_up": False}

        measurement = _scan_for_best_r(clean)
        if measurement is None:
            return {"verified": True, "transcription": verification.transcription,
                    "message": "Recording unclear — please try again in a quieter space.",
                    "cue": "", "score": 0.0, "level_up": False}
        cls      = classify(measurement)
        feedback = generate_feedback(cls, target_word, scores)
        return {
            "verified":      True,
            "transcription": verification.transcription,
            "message":       feedback.message,
            "cue":           feedback.cue,
            "score":         feedback.score,
            "level_up":      feedback.level_up,
            "f3_hz":         cls.f3_hz,
            "error_type":    cls.error_type.value,
        }

    result = await loop.run_in_executor(_executor, _run)
    return JSONResponse(result)


# ── Helpers ────────────────────────────────────────────────────────────────────

def _scan_for_best_r(audio) -> "FormantMeasurement | None":
    """
    Slide a 50ms window across the recording in 20ms steps and return the
    FormantMeasurement with the lowest F3.  The most rhotic moment of any
    utterance has the lowest F3, so this reliably finds /r/ quality without
    needing precise phoneme alignment.
    """
    duration    = len(audio.array) / audio.sample_rate
    window      = 0.05   # 50 ms
    step        = 0.02   # 20 ms
    best        = None
    best_f3     = float("inf")

    t = 0.0
    while round(t + window, 4) <= duration:
        seg = PhonemeSegment(phoneme="r",
                             start_time=round(t, 4),
                             end_time=round(t + window, 4))
        try:
            m = extract_formants(audio, seg)
            if m.f3 < best_f3:
                best_f3 = m.f3
                best    = m
        except ValueError:
            pass
        t += step

    return best


def _ext(filename: str | None) -> str | None:
    if not filename or "." not in filename:
        return None
    return filename.rsplit(".", 1)[-1].lower()


def _report_to_dict(report) -> dict:
    return {
        "transcript":   report.transcript,
        "duration":     report.duration,
        "primary_concern": report.primary_concern.value if report.primary_concern else None,
        "impairment_scores": report.impairment_scores,
        "feedback":     report.feedback,
        "phoneme_results": [
            {
                "phoneme":         r.phoneme,
                "start_time":      r.segment.start_time,
                "end_time":        r.segment.end_time,
                "impairment_type": r.impairment_type.value,
                "error_type":      r.error_type.value,
                "score":           r.score,
                "confidence":      r.confidence,
                "raw_metric":      r.raw_metric,
            }
            for r in report.phoneme_results
        ],
    }
