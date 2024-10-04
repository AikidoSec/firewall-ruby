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
    version = Aikido::Zen::LIBZEN_VERSION
    url_base = "https://github.com/AikidoSec/zen-internals/releases/download"
    artifacts = {
      ".aarch64.dylib" => "libzen_internals_aarch64-apple-darwin.dylib",
      ".x86_64.dylib" => "libzen_internals_x86_64-apple-darwin.dylib",

      ".aarch64.so" => "libzen_internals_aarch64-unknown-linux-gnu.so",
      ".x86_64.so" => "libzen_internals_x86_64-unknown-linux-gnu.so",

      ".x86_64.dll" => "libzen_internals_x86_64-pc-windows-gnu.dll"
    }
    prefix = "lib/aikido/zen/libzen"

    libraries = artifacts.each_key.map { |ext| prefix + ext }

    task download: libraries

    task :clean do
      libraries.each { |lib| rm_f lib }
    end

    rule(/#{prefix}\..*$/) do |task|
      file_name = task.name.gsub(/.*:/, "") # remove rake namespace
      uri = File.join(url_base, "v#{version}", artifacts[file_name.sub(prefix, "")])
      puts "Downloading #{file_name}"
      File.open(file_name, "wb") { |file| copy_stream(URI(uri).open("rb"), file) }

      expected_checksum = URI(uri + ".sha256sum").read.split(/\s+/).first
      actual_checksum = Digest::SHA256.file(file_name).to_s
      if expected_checksum != actual_checksum
        abort "Checksum mismatch on #{file_name}. Expected #{expected_checksum}, got #{actual_checksum}."
      end
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
