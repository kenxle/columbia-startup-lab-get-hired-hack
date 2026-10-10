import json, os, subprocess, urllib.request
LINES = [
 ("s1", "RFQs arrive as shorthand. Every line hides a trap."),
 ("s2", "Sixteen gauge stainless is not point-oh-six-oh inch. And misreads surface after the metal is cut."),
 ("s3", "Opacity is a tax on industrial procurement."),
 ("s4", "Quote Desk shows where every answer came from, flags the paperwork, and asks when it can't tell. Your rep approves and sends."),
 ("s5", "RudCo Quote Desk. Every line shows its work."),
]
INSTR = "Calm, confident, warm narrator for an industrial B2B brand film. Brisk, tight pacing like a 30-second spot, with no long pauses. American accent. No hype."
for name, text in LINES:
    body = json.dumps({"model": "gpt-4o-mini-tts", "voice": "ash", "input": text, "instructions": INSTR, "response_format": "wav", "speed": 1.1}).encode()
    req = urllib.request.Request("https://api.openai.com/v1/audio/speech", data=body,
        headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"], "Content-Type": "application/json"})
    open(f"vo/{name}.wav", "wb").write(urllib.request.urlopen(req).read())
    d = subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",f"vo/{name}.wav"],capture_output=True,text=True).stdout.strip()
    print(name, d)
