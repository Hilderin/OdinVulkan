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
- Reference files with `file_path` only, no line numbers. Line numbers drift as the code evolves, are a pain to keep in sync and add nothing for the reader.

DON'T:
- No jokes, puns or wordplay just for the sake of it.
- No dramatic introductions or theatrical metaphors ("slinging pixels", "see if it smokes", etc.).
- No LLM-style filler ("Let's dive in!", "In this tutorial, we will...", "It's worth noting that...").
- No emoji.
- Don't over-explain trivial things, but don't skip the non-obvious ones either.
- Don't use '—', always use a regular dash '-'


# Documentation format (Jekyll / Just the Docs)

The docs are published with Jekyll using the Just the Docs theme. Two rules to keep them rendering properly:

1. **Every markdown file starts with a Jekyll front matter block**, exactly like `docs/01_test_setup.md`:
   ```
   ---
   title: 01 - Test Setup
   nav_order: 3
   ---
   ```
   `title` is the page title shown in the sidebar. `nav_order` controls where it sits in the nav (lower comes first).

2. **Odin code blocks use the `c` fence**, not `odin`. Jekyll's highlighter (Rouge) doesn't know about Odin, so ` ```odin ` would produce no highlighting at best and a broken build at worst. Use `c` instead, which is close enough and renders fine:
   ````
   ```c
   import "core:fmt"
   ```
   ````

3. **Wrap `{{` in `{% raw %}` / `{% endraw %}` tags.** Jekyll's Liquid template engine sees `{{` and `}}` as variable delimiters. Vulkan struct literals like `{{.COLOR}}` will trigger a build error like `Liquid Exception: Liquid syntax error (line 65): Variable '{{.COLOR}' was not properly terminated with regexp: /\}\}/`. Any doc containing double braces (Odin/Vulkan literals such as `{...{...}}`, `{{0, 0, 0}}`, etc.) must wrap that content in `{% raw %}` and `{% endraw %}`:
   ````
   {% raw %}
   subresourceRange = {{.COLOR}, 0, 1, 0, 1},
   {% endraw %}
   ````
   This applies to both inline code and code blocks. When in doubt, wrap the whole code block.

4. **Keep `docs/index.md` in sync.** Every time a doc page is added (a new step, a reference page), add it to the `docs/index.md` steps table or references list. The index is the reader's entry point - a page that is not linked from it is effectively lost.

Non-Odin blocks (shell commands, expected output) stay as plain ` ``` ` fences without a language, just like the existing docs.


# Code standards
All code must follow the conventions documented in `docs/code_standards.md` (naming, style, compiler flags, Vulkan-specific notes). Read it before writing or editing any Odin code.


# Build command
Always build in "bin/debug" folder.
Always build with the full set of vet/style flags. The project must compile cleanly with:
- `-vet` - unused variables and common mistakes.
- `-strict-style` - enforces style rules.
- `-vet-tabs` - tabs for indentation, no mixing.
- `-disallow-do` - no `do` blocks.
- `-warnings-as-errors` - warnings don't get to hide.

The conventions are documented in `docs/code_standards.md`.

Example:
```
odin build . -debug -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors -out:bin/debug/03_validation_layers
```

To test executable, you need to execute from the root of the main.odin. ex: Working directory needs to be: src/03_validation_layers to execute bin/debug/03_validation_layers

Always use `timeout` when you execute odin run or the executable.


