# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "standard/rake"
require "rake/clean"

load "tasklib/libzen.rake"
load "tasklib/bench.rake"

desc "Run all benchmarks"
task bench: "bench:default"

namespace :build do
  desc "Ensure Gemfile.lock is up-to-date"
  task "update_gem_lockfile" do
    sh "bundle check >/dev/null || bundle"
  end
end
task build: ["build:update_gem_lockfile", "libzen:download:all"]

# Build all the native gems as well
Rake::Task["build"].enhance(["libzen:gems"])

# rake release wants to tag the commit and push the tag, but we run the release
# workflow after creating the tag, and so we don't need another one.
Rake::Task["release:source_control_push"].clear
task "release:source_control_push" do
  # do nothing
end

# Push all the native gems before the libzen-less one.
task "release:rubygem_push" => "libzen:release"

Pathname.glob("sample_apps/*").select(&:directory?).each do |dir|
  namespace :build do
    desc "Ensure Gemfile.lock is up-to-date in the #{dir.basename} sample app"
    task "update_#{dir.basename}_lockfile" do
      Dir.chdir(dir) { sh "bundle check >/dev/null || bundle" }
    end
  end

  task build: "build:update_#{dir.basename}_lockfile"
end

Minitest::TestTask.create do |test_task|
  test_task.test_globs = FileList["test/**/{test_*,*_test}.rb"]
    .exclude("test/e2e/**/*.rb")
end
task test: "libzen:download:current"

Pathname.glob("test/e2e/*").select(&:directory?).each do |dir|
  namespace :e2e do
    desc "Run e2e tests for the #{dir.basename} sample app"
    task dir.basename do
      Dir.chdir(dir) do
        sh "rake ci:setup"
        sh "rake test"
      end
    end
  end

  desc "Run all e2e tests"
  task e2e: "e2e:#{dir.basename}"
end

task default: %i[test standard]
