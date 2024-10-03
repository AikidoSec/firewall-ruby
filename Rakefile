# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "standard/rake"

require_relative "lib/aikido/zen/version"
require "open-uri"

namespace :build do
  desc "Ensure Gemfile.lock is up-to-date"
  task "update_gem_lockfile" do
    sh "bundle check >/dev/null || bundle"
  end

  namespace :internals do
    libraries = %w[lib/aikido/zen/libzen.dylib lib/aikido/zen/libzen.so lib/aikido/zen/libzen.dll]

    url_base = "https://github.com/AikidoSec/zen-internals/releases/download"
    artifacts = {
      ".dylib" => "libzen_internals_x86_64-apple-darwin.dylib",
      ".dll" => "libzen_internals_x86_64-pc-windows-gnu.dll",
      ".so" => "libzen_internals_x86_64-unknown-linux-gnu.so"
    }
    rule %r{lib/aikido/zen/libzen\.(.+)$} do |task|
      version = Aikido::Zen::LIBZEN_VERSION
      uri = File.join(url_base, "v#{version}", artifacts[File.extname(task.name)])
      file_name = task.name.gsub(/.*:/, "") # remove rake namespace
      puts "Downloading #{file_name}"
      File.open(file_name, "wb") { |file| copy_stream(URI(uri).open("rb"), file) }
    end

    task download: libraries

    task :clean do
      libraries.each { |lib| rm_f lib }
    end
  end
end
task build: ["build:update_gem_lockfile", "build:internals:download"]

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
