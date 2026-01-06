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
  - [Code Testing](#code-testing)
    - [Online testing](#online-testing)
    - [Local testing](#local-testing)
  - [Deployment testing](#deployment-testing)

## Standards

### Content

Where possible, describe what is happening, not just where to click and what to type.

### Markdown

1. All content must be written in Markdown. I have a few extensions:
    1. `${toc}` adds a Table of Contents
    1. `${comment @author my comment text}` adds a comment that only appears on the screen when the site run in debug mode.
    1. `${issue @author my issue here}` same as `${comment ... }` but in red.
1. When linking to other markdowns, link them as `.html`. The server will handle the difference.

### Diagramming

1. Use [IBM colours](https://www.ibm.com/design/language/color/) in your diagrams.
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
1. All code samples **must** use the American dialect of English. Dialect usage is not specified for prose as long as it can be understood globally.

## Cookbook

This section is for showing you handy tools for developing this app.

### Environment recommendations

1. Do all testing in the `default` namespace or any namespace other than `jam-in-a-box` or `tools`. This ensures you never forget to specify a namespace.
1. Paste this into your command line for convenience. Because we're specifically avoiding the two namespaces, use the aliases provided by these commands.

    ```sh
    alias oj='oc --namespace=jam-in-a-box'
    alias ot='oc --namespace=tools'
    source <(oc completion $(sed -e 's/^.*\///' <<< "$SHELL"))
    ```

### Code Testing

All code can be tested [online](#online-testing) and static resources (like lab materials) can be tested [locally](#local-testing) too.

#### Online testing

For testing lab materials, markdown-handler, and navigator HTML changes, you'll need to run a configuration script first. This sets up an archive-helper pod and populates it with code from your local desktop.

First, ensure all your code is downloaded your local machine. There are four
repositories, and they must all be downloaded to sister directories. For all of these repositories, you may use a fork, but all but the first one must have the
same folder name. Scripts in the `jam-in-a-box-2` repo will look for files in the others by walking your directory tree to, for example, `../jam-materials`.

```sh
git clone git@github.com:IBMIntegration/jam-in-a-box-2.git
git clone git@github.com:IBMIntegration/jam-navigator.git
git clone git@github.com:IBMIntegration/jam-materials-handler.git
git clone git@github.com:IBMIntegration/jam-materials.git
```

Ensure they are all up to date with:

```sh
# from the jam-in-a-box-2 folder
git pull
for i in jam-navigator jam-materials-handler jam-materials; do
    (cd ../$i; git pull)
done
```

Then convert your deployed Jam-in-a-box environment to a development environment, which creates the archive-helper pod and populates it with local files. You may rerun this script to update all the files.

```sh
scripts/testrun.sh [--copy-materials] [--rebuild-materials-handler]
# --copy-materials             copies the lab materials. This may be a large
#                              copy. If you omit this, then the official files
#                              will remain in place.
# --rebuild-materials-handler  rebuilds the materials handler app. This may
#                              take a while and is only necessary for testing
#                              updates to the app itself. Content updates do not
#                              require this
```

#### Local testing

For lab materials, there is an even quicker way to view the content you are working on with the local testing server.

```sh
cd ../jam-materials-handler
./run-local.sh
```

Then point your browser to [http://localhost:8081/tracks]

### Deployment testing

Custom parameter go in a ConfigMap in the `default` namespace called `jam-setup-options`.

1. Create and log in to the OpenShift / CP4I cluster according to the [README.md](README.md) instructions but do not install the Jam-in-a-box tooling yet.

1. Create a ConfigMap with your custom parameters.

    ```sh
    oc create configmap -n default jam-setup-params --from-literal=parameters="--fork=capnajax --navigator-password=jam --debug"
    ```

    The parameters are:

    - `--canary` or `--canary=*` -- use a git branch other than `main`. If branch is not specified, it'll use the `canary` branch.
    - `--debug` -- adds additional logging and keeps the `jam-setup-pod` open so you can examine the file system after the run is complete.
    - `--fork=*` -- use a specific fork branch other than the main repository (IBMIntegration/jam-in-a-box-2). The forks URLs are named in the `repo-config.json` of the main repository
    - `--navigator-password=*` -- set the navigator password to something of your choosing. By default, it would otherwise set a random password.

    To completely reset the environment before deployment, use:

    ```sh
    ./scripts/reset.sh
    ```

1. Then continue with the deployment. Your local `setup.yaml` copy and your own fork of `setup.yaml` are just as valid as the one on GitHub, but be aware that they will pull build files from the same "official" repositories unless you specify the `--fork` above. Note that this can only use GitHub sources because the Tech Zone environment cannot pull code from your local desktop computer.

    Examples:

    ```sh
    # The "official" setup.yaml
    oc apply -f https://raw.githubusercontent.com/IBMIntegration/jam-in-a-box-2/main/setup.yaml
    ```

    ```sh
    # a forked version (change to your own fork here if you like)
    oc apply -f https://raw.githubusercontent.com/capnajax/integration-jam-in-a-box/main/setup.yaml
    ```

    ```sh
    # local desktop
    oc apply -f ./setup.yaml
    ```

    While this is deploying, you may watch the logs with

    ```sh
    oc logs -n jam-in-a-box jam-setup-pod --tail=-1 -f
    ```

    or you may simply watch the pods come up with

    ```sh
    oc -n jam-in-a-box get po -w
    ```
