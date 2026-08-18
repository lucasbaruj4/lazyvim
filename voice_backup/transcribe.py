import sys, os
from faster_whisper import WhisperModel

# Biases the decoder toward the words Lucas actually says. Without this,
# "Alt+V" comes out as "all V" and "tmux" as "T-Mux".
PROMPT = (
    "Transcript of a software developer dictating to Claude Code in a terminal. "
    "Keyboard shortcuts: Alt+V, Alt+S, Ctrl+C, Ctrl+R, Shift, Esc, F2 prefix. "
    "Tools: tmux, Alacritty, WSL, nvim, git, GitHub, pnpm, npm, bash, jq, curl, "
    "systemd, Piper, Whisper, faster-whisper, Notion, Claude Code, MCP, CLI, TTS, STT. "
    "Concepts: repo, commit, rebase, hook, daemon, venv, aarch64, latency, async, "
    "idempotent, middleware, Postgres, JSON, YAML, stdin, stdout, regex, API."
)

model_size = os.environ.get("WHISPER_MODEL", "small.en")
m = WhisperModel(model_size, device="cpu", compute_type="int8", local_files_only=True)
segs, _ = m.transcribe(sys.argv[1], beam_size=1, vad_filter=True,
                       condition_on_previous_text=False, initial_prompt=PROMPT)
print(" ".join(s.text.strip() for s in segs).strip())
