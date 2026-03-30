# Bug template

This is a bug template for reporting bugs to the Kleaf team. Using the template
can help the Kleaf team identify the issue sooner.

## TEMPLATE

### Kernel Branch

_e.g. `common-android-mainline`. If this is not a branch on AOSP Gerrit, please
provide the full `repo init` command to initialize the manifest._

_For partners who the manifest branches aren't accessible to Google, please
provide the output of the following command instead:_

```
repo forall -c 'echo $REPO_PATH:$(git log --oneline -1)'
```

### Reproducibility

_Does the issue happen only once? Rarely? Frequently? Or 100% reproducible?_

### Repro steps

_Please provide the following:_
- _Changes to cherry-pick, if any_
- _Any extra steps you make to set up the environment to reproduce the error_
- _`bazel` command(s) to run._
  - _Always add `--verbose_failures --announce_rc --debug_annotate_scripts` to
    the command for detailed error message._

_Example: "Cherry-pick the attached patch, then run the following command:"_

```
bazel run --verbose_failures --announce_rc --debug_annotate_scripts //common:kernel_dist -- --dist_dir=out/dist
```

### Expected result

_e.g. "Build should pass."_

### Actual result

_e.g. "Build fails with the attached terminal output."_

_Always attach the **full** terminal output, including stdout and stderr, not
just the error message._

### Additional comments

_For example:_
- _Do you think this is a regression?_
- _Do you think which changes or lines may be the culprit?_
- _Is this issue important or urgent? Why? Does it block anything?_
