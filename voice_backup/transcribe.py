import sys, os
from faster_whisper import WhisperModel

# Biases the decoder toward the words Lucas actually says. Without this,
# "Alt+V" comes out as "all V" and "tmux" as "T-Mux".
PROMPT = (
    # Whisper accepts at most 224 tokens of prompt and silently truncates past
    # that. This is ~178; check with the tokenizer before adding more.
    "Transcript of a software developer dictating to Claude Code in a terminal. "
    "Shortcuts: Alt+V, Alt+S, Ctrl+C, F2 prefix. "
    "Repos: lucasvim, GLOBAL.md, pretty-little-skills, patrick, thesis, DishRoll, bashfolio. "
    "Tools: tmux, Alacritty, WSL, WSLg, nvim, git, GitHub, pnpm, bash, jq, curl, systemd, "
    "Piper, Whisper, faster-whisper, Notion, MCP, CLI, TTS, STT, PulseAudio, paplay. "
    "Concepts: repo, commit, rebase, hook, daemon, venv, aarch64, latency, buffer, "
    "clipping, transcribe, dictate, stdin, stdout, JSON, regex."
)

model_size = os.environ.get("WHISPER_MODEL", "small.en")
m = WhisperModel(model_size, device="cpu", compute_type="int8", local_files_only=True)
segs, _ = m.transcribe(sys.argv[1], beam_size=1, vad_filter=True,
                       condition_on_previous_text=False, initial_prompt=PROMPT)
print(" ".join(s.text.strip() for s in segs).strip())
