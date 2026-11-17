# Language files

One directory per language code, the value of `WHISPER_LANG` (`en` by default):

- `fillers.txt`: one filler or hesitation per line. `just transcribe-verbatim` puts them in the prompt so whisper keeps them, and `just stats` counts them. Multi-word entries are fine.
- `smoke-test.txt`: the sentence `just test` synthesizes with a macOS voice of that language, then the word it expects in the transcript.
- `prompt.example.txt`: a generic vocabulary prompt, tracked in git.
- `prompt.txt`: your own vocabulary prompt, git-ignored. `just prompt` creates it from the example; `just transcribe` uses it when it exists and the example otherwise. Keep it short, in the language of the recording, and list the names and terms you want spelled right.

To add a language, create the directory with the three tracked files. Without a directory, transcription still works: no prompt, no filler count, and `just test` asks for a language it knows.
