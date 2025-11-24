# Contributing to the jam-in-a-box

The purpose of this document is to establish standards and provide useful tips for developing content and maintaining this site.

## Table of Contents

- [Standards](#standards)
  - [Content](#content)
  - [Markdown](#markdown)
  - [Diagramming](#diagramming)
  - [Screenshotting](#screenshotting)
  - [Language](#language)
- [Cookbook](#cookbook)
  - [Environment recommendations](#environment-recommendations)
  - [Custom parameter deployments](#custom-parameter-deployments)
  - [Updating HTML](#updating-html)

## Standards

### Content

Where possible, describe what is happening, not just where to click and what to type.

### Markdown

1. All content must be written in Markdown. I have a few extensions:
    1. `${toc}` adds a Table of Contents
1. When linking to other markdowns, link them as `.html`. The server will handle the difference.

### Diagramming

1. Use IBM colours in your diagrams.
1. Favour SVG for diagrams so they can be modified later if necessary.

### Screenshotting

1. Sizing:
    1. Use the smallest window size that makes sense.
    1. Avoid resizing or otherwise changing the browser window. Ideally, do all the screenshots in one sitting.
1. Inclusion:
    1. When possible, include header of the web page you are screenshotting. This helps provide context to the reader. Do not do this if the key parts of the screen are too far down from the top.
    1. Only screenshot content -- do not include the browser window frame, URL bar, tabs, etc. It should not be possible to tell what browser or operating system you are using to screenshot.
1. Outline buttons, fields, etc that we're talking about in red. Let the user know what you are talking about.
1. Err on the side of excessive. It's ok to have "too many" screenshots.
1. Favour PNG files.
1. Give the PNG files simple names like `[prefix][number].png`. Keep your numbers in order. If you miss a number and you need to insert a screenshot, don't renumber them. Just add a `-1`, `-2`, e.g.: `MD1.png`, `MD2.png`, `MD3.png`, `MD3-1.png`, `MD4.png`...

### Language

1. Use inclusive language.
    1. Remember that plain language is inclusive language. Unly use metahpores worth explaining.
1. Speak to the reader in the second person, imperative tense when it makes sense, but be careful about tone.
1. All code samples must use the American dialect of English.

## Cookbook

This section is for showing you handy tools for developing this app.

### Environment recommendations

1. Do all testing in the `default` namespace or any namespace other than `jam-in-a-box` or `tools`. This ensures you never forget to specify a namespace.
1. Paste this into your command line for convenience

    ```sh
    alias oj='oc --namespace=jam-in-a-box'
    alias ot='oc --namespace=tools'
    if [ "$SHELL" == '/bin/bash' ]; then source <(oc completion bash); fi
    if [ "$SHELL" = '/bin/zsh' ]; then source <(oc completion zsh); fi
    ```

1. Use a post-commit hook to update archive files before checking content in. Set up the post-commit hook with

    ```sh
    scripts/setup-hooks.sh
    ```

### Custom parameter deployments

Custom parameter go in a ConfigMap in the `default` namespace called `jam-setup-options`.

1. Create and log in to the OpenShift / CP4I cluster according to the [README.md](README.md) instructions but do not install the Jam-in-a-box tooling yet.

1. Create a ConfigMap with your custom parameters.

    ```sh
    oc create configmap -n default jam-setup-params --from-literal=parameters="--clean --start-here-app-password=jam --canary"
    ```

    The parameters are:

    - `--canary` or `--canary=*` -- use a git branch other than `main`. If branch is not specified, it'll use the `canary` branch.
    - `--clean` -- removes all preëexisting materials before deploying.
    - `--fork=*` -- use a specific fork branch other than the main repository (IBMIntegration/jam-in-a-box-2). The forks URLs are named in the `repo-config.json` of the main repository
    - `--start-here-app-password=*` -- set the jam-in-a-box password to something of your choosing. By default, it would otherwise set a random password.

1. Then continue with the deployment

    ```sh
    oc apply -f https://raw.githubusercontent.com/IBMIntegration/jam-in-a-box-2/main/setup.yaml
    ```

### Updating HTML

To quickly update most HTML for the `jam-in-a-box` app for testing, there's a script to watch the `htdocs` folder and automatically upload changes to the pod.

```sh
scripts/watch-and-sync.sh
```
