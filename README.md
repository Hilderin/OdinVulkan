# Odin Vulkan Tutorial
This repository contains my work adapting the official Vulkan Tutorial from the Khronos site [https://docs.vulkan.org/tutorial/latest/00_Introduction.html](https://docs.vulkan.org/tutorial/latest/00_Introduction.html) to the Odin language.

The tricky part is that this version of the tutorial uses C++ with RAII classes rather than the C version of the Vulkan API, which is further from Odin since Odin doesn't support classes or object-oriented programming. The original [Vulkan Tutorial](https://vulkan-tutorial.com) was therefore a great help in putting this repository together.

Interesting details:
- Odin version dev-2026-07
- API Vulkan 1.4
- Slang as the shader language

> **Attribution:** This project is inspired by the [Khronos Vulkan® Tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html) (licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)) and the original [Vulkan Tutorial](https://vulkan-tutorial.com) by Alexander Overvoorde. The code and text in this repository are original work written in Odin and licensed under the [MIT License](./LICENSE).


## How to use this repository

The [docs](docs/index.md) contains the tutorial explanations.
The [src](src) contains a folder per project, each project is a step in the tutorial.

Each project is self-contained and configured to run in VSCode. You should open each project folder in VSCode directly.


## Prerequisites
Follow instructions in the [prerequisites section](docs/prerequisites.md).


## Preview the docs locally

The documentation is a Jekyll site using the Just the Docs theme. To preview it on your machine before pushing:

```bash
cd docs/
bundle config set --local path vendor/bundle
bundle install
bundle exec jekyll serve --source .
```

Open `http://127.0.0.1:4000` in your browser. The site rebuilds automatically when you edit a file.

Requires Ruby and Bundler (`sudo apt install ruby ruby-dev build-essential && sudo gem install bundler`).



## References
- [Khronos Vulkan® Tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html)
- [The Vulkan Guide](https://docs.vulkan.org/guide/latest/index.html)
- [Vulkan Samples](https://docs.vulkan.org/samples/latest/README.html)
- [Vulkan Tutorial](https://vulkan-tutorial.com)
- [Slang language](https://shader-slang.org)
- [Odin Documentation](https://odin-lang.org/docs/)
- [Odin Examples](https://github.com/odin-lang/examples)
