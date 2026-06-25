from .models import ClassificationResult, ErrorType, FeedbackResult

LEVEL_UP_THRESHOLD   = 0.8
LEVEL_UP_CONSECUTIVE = 3

_MESSAGES = {
    ErrorType.CORRECT:        ("Great /r/ on '{word}'!",
                               "Keep your lips neutral and tongue tip curled slightly."),
    ErrorType.W_SUBSTITUTION: ("Almost — your lips are rounding.",
                               "Square your lips and press the sides of your tongue against your upper back teeth."),
    ErrorType.L_SUBSTITUTION: ("Close — watch your tongue tip.",
                               "Don't let your tongue touch the roof of your mouth. Curl it back without contact."),
    ErrorType.PARTIAL:        ("Getting there — hold the /r/ a bit longer.",
                               "Sustain the tongue position through the vowel that follows."),
    ErrorType.UNCLEAR:        ("Recording unclear — try again in a quieter space.", ""),
}


def generate_feedback(
    result: ClassificationResult,
    target_word: str,
    session_scores: list[float],
) -> FeedbackResult:
    message_tmpl, cue = _MESSAGES[result.error_type]
    message = message_tmpl.format(word=target_word)

    all_scores = session_scores + [result.rhoticity_score]
    level_up = (
        len(all_scores) >= LEVEL_UP_CONSECUTIVE
        and all(s >= LEVEL_UP_THRESHOLD for s in all_scores[-LEVEL_UP_CONSECUTIVE:])
    )

    return FeedbackResult(
        message=message,
        cue=cue,
        score=result.rhoticity_score,
        level_up=level_up,
    )
