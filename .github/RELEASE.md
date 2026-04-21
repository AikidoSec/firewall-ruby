# Releasing a new version

This document describes how to cut a new release of the `aikido-zen` gem.

The process is two steps: first a **version-bump PR** is merged to `main`, then a **GitHub release** is published which triggers the publish-to-RubyGems workflow.

## 1. Open the version-bump PR

The gem version is read from `lib/aikido/zen/version.rb` (`Aikido::Zen::VERSION`) by `aikido-zen.gemspec`. That same constant is baked into every `Gemfile.lock` under the `PATH` block as `aikido-zen (X.Y.Z)`, so the bump touches the version constant **and** every lockfile.

### Steps

1. Branch from up-to-date `main`:

   ```sh
   git switch main && git pull
   git switch -c prepare-X.Y.Z
   ```

2. Bump the `VERSION` constant in `lib/aikido/zen/version.rb`. Do **not** touch `LIBZEN_VERSION` — that tracks `zen-internals` and is bumped independently.

3. Replace the version in every lockfile in one pass:

   ```sh
   find gemfiles sample_apps -name "*.gemfile.lock" \
     -exec sed -i '' 's/aikido-zen (OLD)/aikido-zen (NEW)/' {} +
   ```

   (Drop the `''` after `-i` on Linux.) This should change exactly **24 lockfiles**:
   - `gemfiles/ruby-{2.7,3.0,3.1,3.2,3.3,3.4}.gemfile.lock` (6)
   - `sample_apps/rails7.1_{path_traversal,sql_injection,template}/gemfiles/ruby-{2.7,3.0,3.1,3.2,3.3,3.4}.gemfile.lock` (18)

4. Commit, push, and open a PR titled `Prepare X.Y.Z`:

   ```sh
   git commit -am "Prepare X.Y.Z"
   git push -u origin prepare-X.Y.Z
   gh pr create --title "Prepare X.Y.Z" --body "Bumps \`aikido-zen\` to vX.Y.Z."
   ```

6. Get review, wait for CI green, merge to `main`.

> **Heads-up:** if any test asserts a User-Agent like `"firewall-ruby vX.Y.Z"` with the version hardcoded (rather than interpolating `Aikido::Zen::VERSION`), CI will fail on the bump PR. Replace the literal with `"firewall-ruby v#{Aikido::Zen::VERSION}"` and re-push.

## 2. Publish the GitHub release

`.github/workflows/release.yml` listens for `release: published` events. Creating the release tags the commit, and the workflow then builds the native gems (one per supported platform via `tasklib/libzen.rake`) and publishes them to RubyGems alongside the platform-agnostic gem.

### Steps

1. Make sure your local `main` is at the merged bump commit:

   ```sh
   git switch main && git pull
   ```

2. Draft the release notes by listing the user-facing changes since the previous release. Mirror the style of [v1.1.1](https://github.com/AikidoSec/firewall-ruby/releases/tag/v1.1.1):

   ```
   ## What's Changed

   - <Change one>
   - <Change two>
   ```

   `gh pr list --state merged --base main --search "merged:>YYYY-MM-DD"` is a quick way to enumerate merged PRs since the last release.

3. Publish the release. The tag must be `vX.Y.Z` (lowercase `v` prefix — matches every prior release):

   ```sh
   gh release create vX.Y.Z \
     --repo AikidoSec/firewall-ruby \
     --target main \
     --title vX.Y.Z \
     --notes-file release-notes.md
   ```

   Or use the GitHub UI: **Releases → Draft a new release**, create the new tag `vX.Y.Z` against `main`, paste the notes, **Publish**.

4. Watch the workflow: <https://github.com/AikidoSec/firewall-ruby/actions/workflows/release.yml>. On success, the new gem versions appear at <https://rubygems.org/gems/aikido-zen>.

## Beta releases

Beta releases let you ship an in-progress change for staging or customer validation before cutting a stable version. They follow the same two-step flow (version-bump PR → GitHub release), with three differences: the version string, the branch/commit naming, and publishing the GitHub release as a **pre-release**.

RubyGems treats any version string containing letters (e.g. `1.0.2.beta.1`) as a pre-release: it won't be resolved by `gem install aikido-zen` or by a plain `gem "aikido-zen"` Gemfile entry. Consumers opt in explicitly with `gem install aikido-zen --pre` or `gem "aikido-zen", ">= 0.a"`.

### 1. Open the version-bump PR

Same as the stable process, with these substitutions:

- Version format: `X.Y.Z.beta.N` — reuse the `X.Y.Z` of the stable release you're iterating toward, incrementing `N` for each beta (see `v1.0.2.beta.1` … `v1.0.2.beta.10` for the existing pattern).
- Branch name: `prepare-X.Y.Z.beta.N`.
- Commit / PR title: `Bump version to X.Y.Z.beta.N` (matches prior betas).
- Bump `VERSION` in `lib/aikido/zen/version.rb` to `"X.Y.Z.beta.N"`.
- Run the same lockfile `sed` across all 24 lockfiles, replacing `aikido-zen (OLD)` with `aikido-zen (X.Y.Z.beta.N)`.

Everything else (review, CI, merge to `main`) is unchanged.

### 2. Publish the GitHub pre-release

Identical to the stable flow, but pass `--prerelease` so the release is flagged `Pre-release` and does **not** replace the current "Latest" release on GitHub or RubyGems:

```sh
gh release create vX.Y.Z.beta.N \
  --repo AikidoSec/firewall-ruby \
  --target main \
  --title vX.Y.Z.beta.N \
  --prerelease \
  --notes-file release-notes.md
```

Or, in the GitHub UI: **Releases → Draft a new release**, tag `vX.Y.Z.beta.N` against `main`, tick **Set as a pre-release**, **Publish**.

The `verify-version` job in `.github/workflows/release.yml` compares the tag against `v${Aikido::Zen::VERSION}`, so beta tags pass through with no workflow changes. The same `release.yml` job builds and pushes the native gems to RubyGems.

### 3. Promoting a beta to stable

There is no automatic promotion. Once a beta is validated, cut a normal `X.Y.Z` release following the stable flow above — that publishes a separate gem version and becomes the new "Latest".

## Troubleshooting

- **Release workflow failed before publishing any gem.** Safe to re-run from the Actions tab once the cause is fixed; the release/tag stay in place.
- **Some platform gems pushed but others failed.** Native gems are pushed one at a time (`tasklib/libzen.rake`'s `libzen:release`). RubyGems rejects re-pushes of an already-published version, so re-running the workflow after a partial failure is safe — the already-pushed platforms will error and the missing ones will go through. If that gets messy, bump to `X.Y.Z+1` and re-release rather than fighting it.
- **Tag name typo (e.g. `1.1.2` instead of `v1.1.2`).** Delete the GitHub release *and* the tag (`git push --delete origin <tag>`), then recreate. Don't leave a half-published version on RubyGems.
