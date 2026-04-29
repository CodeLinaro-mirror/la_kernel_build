---
name: docs-updater
description: Updates Kleaf API documentation by reading instructions from BUILD.bazel and checks for git differences.
---
# Instructions

To update the Kleaf API documentation, follow these steps:

1.  **Find Commands**: Read `build/kernel/kleaf/docs/BUILD.bazel` and look for the docstring (usually at the top of the file) that describes how to update the documentation.
    *   The commands are typically in a code block in the file docstring.
2.  **Execute Update**: Extract the commands found in the file and run them in the workspace root.
    *   *Note*: The `bazel run` command would take a few minutes, but no more than that. If it takes more than a few minutes, consider it stuck. In that case, dump the `stdout`/`stderr` of the process and ask the user what to do next.
3.  **Check for Changes**: After running the update commands, run `git status` and `git diff` in the `build/kernel/kleaf/docs/api_reference` directory to see if there are any modifications or new files.
4.  **Summarize and Report**: Summarize any differences found and report them to the user.
    *   Use specific examples in the summary, such as:
        *   foo rule is added
        *   bar macro is deleted
        *   the foo(bar=) attribute is added
        *   the foo rule is modified:
            *   bar attribute added
            *   baz attribute modified the type
            *   qux attribute update docs to do X
