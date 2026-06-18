import numpy as np
import sounddevice as sd
import noisereduce as nr
import librosa
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC
import torch


def record_audio(seconds=3):
    print("Recording... Speak clearly.")
    sr = 16000
    audio_array = sd.rec(int(seconds * sr), samplerate=sr, channels=1, dtype='float32')
    sd.wait()
    audio_array = audio_array.squeeze()
    print("Recording complete.")
    return audio_array, sr


def preprocess_audio(audio_array, sr=16000):
    print("Applying spectral noise reduction...")
    reduced_noise_audio = nr.reduce_noise(
        y=audio_array,
        sr=sr,
        stationary=True,
        prop_decrease=0.8
    )
    trimmed_audio, _ = librosa.effects.trim(reduced_noise_audio, top_db=25)
    print("Audio cleaned and trimmed.")
    return trimmed_audio


model_id = "speech31/wav2vec2-large-english-phoneme-v2"

print(f"Loading processor and model for {model_id}...")
processor = Wav2Vec2Processor.from_pretrained(model_id)
model = Wav2Vec2ForCTC.from_pretrained(model_id)

device = "cuda" if torch.cuda.is_available() else "cpu"
model = model.to(device)
print(f"Model loaded successfully on {device}.")


def analyze_utterance(audio_array):
    inputs = processor(audio_array, sampling_rate=16000, return_tensors="pt", padding=True)
    input_values = inputs.input_values.to(device)

    with torch.no_grad():
        logits = model(input_values).logits

    predicted_ids = torch.argmax(logits, dim=-1)
    transcription = processor.batch_decode(predicted_ids)[0]
    probabilities = torch.nn.functional.softmax(logits, dim=-1).squeeze(0)

    return transcription, probabilities, predicted_ids.squeeze(0)


def verify_rhoticity(transcription, probabilities, predicted_ids, target_word="red"):
    print(f"Target Word Context: {target_word.upper()}")
    print(f"Raw Phonetic Transcription: Out: {transcription}")

    has_r = any(char in transcription for char in ['ɹ', 'r'])
    has_w_substitution = 'w' in transcription

    print("\n--- Diagnostic Evaluation ---")
    if has_r:
        print("Success: Rhoticity detected in the audio signal.")
    elif has_w_substitution:
        print("Correction: Potential Labiodental Substitution Detected ('W' sound instead of 'R').")
        print("Cue: Focus on keeping lips neutral/square. Pull the sides of your tongue up to your upper molars.")
    else:
        print("Warning: Sound distorted or omitted. The target phoneme was not reached.")


if __name__ == "__main__":
    audio, sr = record_audio(seconds=3)
    clean_audio = preprocess_audio(audio, sr=sr)
    transcription, probabilities, predicted_ids = analyze_utterance(clean_audio)
    verify_rhoticity(transcription, probabilities, predicted_ids, target_word="red")
