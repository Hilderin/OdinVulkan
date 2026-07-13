# Project
This project is based on Vulkan Tutorial from Khronos and aims to learn and teach Vulkan using Odin without any bootstrap.
I'm following the Vulkan Tutorial but I don't want be reproduce exactly the same tutorial.

I want something more personnal, for the love of coding and learning Graphics Programming in a nice language Odin.

Each src folder is an evolutionary step from the previous step/src.

The documentation goes in the docs folder as markdown files to distribute on github.
All the code and documentation are in english. I don't want to sound like a LLMs or IA, the text needs to be human, easy to read, in a popular language.


# Documentation tone

The docs should sound like a real person explaining things, not a textbook and not an AI.
Aim for the tone of a friendly developer talking to a peer, not a stand-up comedian.

DO:
- Write in a simple, direct, everyday language.
- Keep it warm and human: short asides, light personal notes and honest opinions are welcome.
- Explain the "why" behind each step, not just the "what".
- Point out the common pitfalls and recurring Vulkan patterns the reader will encounter.
- Use `file_path:line_number` references when pointing to specific code.
- One markdown file per src step, following the format defined in `docs/01_test_setup.md`:
  1. Short intro: what this step is about and why it matters.
  2. "What we want to prove" / goal of the step.
  3. "The code, step by step": each code block explained, line by line when useful.
  4. "Run it": the exact command and the expected output.
  5. "What's next": a short teaser for the next step.

DON'T:
- No jokes, puns or wordplay just for the sake of it.
- No dramatic introductions or theatrical metaphors ("slinging pixels", "see if it smokes", etc.).
- No LLM-style filler ("Let's dive in!", "In this tutorial, we will...", "It's worth noting that...").
- No emoji.
- Don't over-explain trivial things, but don't skip the non-obvious ones either.


# Code standards
All code must follow the conventions documented in `docs/code_standards.md` (naming, style, compiler flags, Vulkan-specific notes). Read it before writing or editing any Odin code.


# Build command
Always build in "bin/debug" folder.
Always build with the full set of vet/style flags. The project must compile cleanly with:
- `-vet` — unused variables and common mistakes.
- `-strict-style` — enforces style rules.
- `-vet-tabs` — tabs for indentation, no mixing.
- `-disallow-do` — no `do` blocks.
- `-warnings-as-errors` — warnings don't get to hide.

The conventions are documented in `docs/code_standards.md`.

Example:
```
odin build . -debug -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors -out:bin/debug/03_validation_layers
```
