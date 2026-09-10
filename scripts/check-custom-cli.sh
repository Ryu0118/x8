#!/bin/sh
set -eu

# An independent build detects accidental imports of package-only APIs.
swift build --package-path Examples/CustomStorageCLI \
  --scratch-path .build/example-cli --experimental-prune-unused-dependencies
example_bin=$(swift build --package-path Examples/CustomStorageCLI \
  --scratch-path .build/example-cli --show-bin-path)

for module in X8Config X8S3 Yams SotoCore SotoS3; do
  test ! -e "$example_bin/Modules/$module.swiftmodule"
done

"$example_bin/ExampleCache" --help
EXAMPLE_CACHE_DOMAIN=example "$example_bin/ExampleCache" config validate
EXAMPLE_CACHE_DOMAIN=example "$example_bin/ExampleCache" config show
EXAMPLE_CACHE_DOMAIN=example "$example_bin/ExampleCache" doctor

if purge_output=$(EXAMPLE_CACHE_DOMAIN=example "$example_bin/ExampleCache" \
  cache purge --scope staging --older-than 1d --dry-run 2>&1); then
  echo 'Expected the example storage to reject administration.' >&2
  exit 1
fi
case "$purge_output" in
  *'does not support cache administration.'*) ;;
  *) echo "$purge_output" >&2; exit 1 ;;
esac
