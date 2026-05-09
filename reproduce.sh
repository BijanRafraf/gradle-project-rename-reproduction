#!/bin/bash
#
# Reproduces a Gradle issue where renaming a subproject leaves stale .class
# files in the shared build/ directory.
#
# What happens:
#   1. Compile mymodule under task path :foo:compileTestJava — produces
#      StaysFile.class and OrphanFile.class in mymodule/build/classes/java/test/.
#   2. Delete OrphanFile.java from the source set AND rename the subproject
#      from :foo to :bar in settings.gradle. The on-disk directory (mymodule)
#      and the output directory (mymodule/build) are unchanged.
#   3. Compile mymodule under task path :bar:compileTestJava.
#
# Expected: OrphanFile.class is removed (no source produces it).
# Actual:   OrphanFile.class survives.
#
# Why: Gradle's stale-output cleanup is keyed by task path. :bar:compileTestJava
# has no prior snapshot that lists OrphanFile.class, so the cleanup walks an
# empty (or different) set of files and never deletes it. javac then runs over
# only the current source set, leaving OrphanFile.class untouched.

set -euo pipefail
cd "$(dirname "$0")"

reset_to_baseline() {
    cp fixtures/settings-foo.gradle settings.gradle

    mkdir -p mymodule/src/test/java/example
    cp fixtures/StaysFile.java mymodule/src/test/java/example/StaysFile.java
    cp fixtures/OrphanFile.java mymodule/src/test/java/example/OrphanFile.java

    rm -rf mymodule/build .gradle
}

apply_rename_and_source_removal() {
    cp fixtures/settings-bar.gradle settings.gradle
    rm -f mymodule/src/test/java/example/OrphanFile.java
}

list_test_classes() {
    if [[ -d mymodule/build/classes/java/test/example ]]; then
        ls -lh mymodule/build/classes/java/test/example
    else
        echo "(no output dir yet)"
    fi
}

echo "Resetting to baseline (project :foo, both source files present)"
reset_to_baseline

echo
echo "Step 1: build :foo:compileTestJava"
./gradlew :foo:compileTestJava --warn

echo
echo "  Output classes after step 1:"
list_test_classes

echo
echo "Step 2: rename :foo -> :bar and delete OrphanFile.java"
apply_rename_and_source_removal

echo
echo "Step 3: build :bar:compileTestJava"
./gradlew :bar:compileTestJava --warn

echo
echo "  Output classes after step 3:"
list_test_classes

echo
if [[ -f mymodule/build/classes/java/test/example/OrphanFile.class ]]; then
    echo "RESULT: BUG REPRODUCED — OrphanFile.class is still present even though"
    echo "        OrphanFile.java was deleted before the second build."
    exit 1
else
    echo "RESULT: not reproduced — OrphanFile.class was correctly cleaned up."
fi
