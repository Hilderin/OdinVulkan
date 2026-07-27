---
title: Setup Documentation Site
nav_order: 98
---

# Setup Documentation Site

The documentation you are reading right now is a [Jekyll](https://jekyllrb.com/) site using the [Just the Docs](https://just-the-docs.com/) theme. If you want to preview it locally before pushing changes, here is how.

## Prerequisites

You need Ruby and Bundler:

- **Linux (Debian/Ubuntu)**:
  ```
  sudo apt install ruby ruby-dev build-essential
  sudo gem install bundler
  ```
- **macOS**: Ruby comes preinstalled. Install Bundler with `sudo gem install bundler`.
- **Windows**:
  - Install Ruby from [rubyinstaller.org](https://rubyinstaller.org/).
    IMPORTANT: Install version 3.3.x to avoid compatibility issues with Ruby 3.4 and later.
    Either the `With DevKit` or `Without DevKit` package works. The important step is the checkbox at the end of the installer: **"Run 'ridk install' to set up MSYS2 and development toolchain"**. Leave it checked. When the terminal opens, type `3` and press Enter to install MSYS2 and MINGW -- Jekyll needs them to build native gems.
    Also make sure **"Add Ruby executables to your PATH"** is checked during installation.
  - Then `gem install bundler` in a terminal.

## Build and serve

```bash
cd docs/
bundle config set --local path vendor/bundle
bundle install
bundle exec jekyll serve --source .
```

Open `http://127.0.0.1:4000` in your browser. The site rebuilds automatically when you edit a file.

## What each file does

- `docs/_config.yml` -- theme settings, color scheme, navigation, footer, callouts
- `docs/index.md` -- home page with the step-by-step table
- `docs/*.md` -- each page of the tutorial
- `docs/assets/` -- images and other static files
- `docs/_includes/` -- custom HTML snippets (if any)
- `docs/_sass/` -- custom CSS overrides
- `docs/Gemfile` -- Ruby dependency manifest (Jekyll and Just the Docs versions)
