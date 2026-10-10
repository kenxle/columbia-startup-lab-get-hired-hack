# Voiceover for promo v2. Same voice and instructions as vo.py.
# Writes audio/<name>_v2_raw.wav, then audio/<name>_v2.wav fitted to its shot window.
import json, os, subprocess, urllib.request
# (name, start second, max length in seconds, API speed, text) -- text is verbatim from SHOT_LIST.md.
# Shots 5 and 7 have no voiceover, so the lines before them may run a little into them.
LINES = [
 ("vo1", 0.15, 2.80, 1.10, "RFQs are the lifeblood of our company."),
 ("vo2", 3.05, 2.35, 1.10, "We promise 24 hour turnaround"),
 ("vo3", 5.60, 6.80, 1.10, "but we also require accuracy and the cost of an error can be hundreds of thousands of dollars"),
 ("vo4", 12.55, 4.40, 1.25, "Sixteen gauge stainless reads point-oh-six-two-five inch, by the stainless gauge table."),
 ("vo6", 18.55, 3.30, 1.20, "It flags unwritten paperwork and names the trigger word."),
 ("vo9", 25.55, 4.35, 1.30, "Every line shows its work. The agent prepares the conversation, and the rep owns it."),
]
INSTR = "Calm, confident, warm narrator for an industrial B2B brand film. Brisk, tight pacing like a 30-second spot, with no long pauses. American accent. No hype."
def dur(p):
    return float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",p],capture_output=True,text=True).stdout.strip())
if __name__ == "__main__":
    import sys
    # python3 vo_v2.py            -> generate all lines
    # python3 vo_v2.py vo1 vo4     -> regenerate only those, refit the rest
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    for name, start, maxlen, speed, text in LINES:
        raw = f"audio/{name}_v2_raw.wav"
        if (not only or name in only) or not os.path.exists(raw):
            body = json.dumps({"model": "gpt-4o-mini-tts", "voice": "ash", "input": text, "instructions": INSTR, "response_format": "wav", "speed": speed}).encode()
            req = urllib.request.Request("https://api.openai.com/v1/audio/speech", data=body,
                headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"], "Content-Type": "application/json"})
            open(raw, "wb").write(urllib.request.urlopen(req).read())
        # trim silence at both ends, then speed up only if it overruns its window
        trimmed = f"audio/{name}_v2_trim.wav"
        subprocess.run(["ffmpeg","-y","-v","error","-i",raw,"-af",
            "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse",
            trimmed], check=True)
        d = dur(trimmed); tempo = max(1.0, d / maxlen)
        subprocess.run(["ffmpeg","-y","-v","error","-i",trimmed,"-af",f"atempo={tempo:.4f}",f"audio/{name}_v2.wav"], check=True)
        print(name, f"raw {d:.2f}s", f"tempo {tempo:.3f}", f"final {dur(f'audio/{name}_v2.wav'):.2f}s (window {maxlen})")
