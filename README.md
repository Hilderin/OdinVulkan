# Odin Vulkan Tutorial
This repository contains instructions and tutorial to use Vulkan in Odin from scratch. It aims to explain in detail every aspect of using Vulkan in Odin from the installation process to more advanced tutorials on shaders, computed shaders, lighting, shadow, etc...

This tutorial goes in pair with https://docs.vulkan.org/tutorial/latest/00_Introduction.html which uses Vulkan 1.4, Dynamic rendering, Timeline semaphore and Slang.


## How to use this repository

The [docs](docs/README.md) contains the tutorials explanations.

Each project is self contained and configure to run in VSCode. You should open each project folder in VSCode directly.


## Setup process

### Prerequisites
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

## Todo:

- Documentation for odinfmt.json









## References

https://docs.vulkan.org/tutorial/latest/00_Introduction.html

https://vulkan-tutorial.com