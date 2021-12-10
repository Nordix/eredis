Contributing to eredis
======================

Requirements: Erlang/OTP, rebar3 and make. For tests, also Docker and OpenSSL.

* `make test` runs the tests using Docker and generates TLS certificates using
  OpenSSL. If you can't run it or if some test (e.g. the IPv6 test) fails, it's
  fine as long as it passes in the automated builds.
* When docs are affected, run `make edoc` and commit the changed Markdown files
  under `doc/`.
* Don't update the version unless agreed with the maintainers.

Releasing a new version
-----------------------

Normally done by the maintainers.

* Update the version in `src/eredis.app.src` and `mix.exs`.
* Update CHANGELOG.md and add what's new since the last version. (Use e.g. `git
  log *PREV_VERSION*..HEAD`).
* Check that documentation is generated and committed using `make edoc`.
* Commit the changes, push and check the build.
* Publish to Hex using `make publish` (requires `mix` and a Hex account with
  rights to publish this project). (This can be done later.)
* Create an annotated tag on the form vMAJOR.MINOR.PATCH, `git tag -a v0.0.0`.
  Write a very short message with the most important changes (one line or a few
  bullets).
* Push the tag using `git push --tags`.
