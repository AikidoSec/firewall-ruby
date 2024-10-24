# frozen_string_literal: true

require "open-uri"
require "rubygems/package_task"

require_relative "../lib/aikido/zen/version"

LibZenDL = Struct.new(:os, :arch, :artifact) do
  def download
    puts "Downloading #{path}"
    File.open(path, "wb") { |file| FileUtils.copy_stream(URI(url).open("rb"), file) }
  end

  def verify
    expected = URI(url + ".sha256sum").read.split(/\s+/).first
    actual = Digest::SHA256.file(path).to_s

    if expected != actual
      abort "Checksum mismatch on #{path}: Expected #{expected}, got #{actual}."
    end
  end

  def version
    "v#{Aikido::Zen::LIBZEN_VERSION}"
  end

  def path
    [prefix, arch, ext].join(".")
  end

  def prefix
    "lib/aikido/zen/libzen-#{version}"
  end

  def ext
    case os
    when :darwin then "dylib"
    when :linux then "so"
    when :windows then "dll"
    end
  end

  def url
    File.join("https://github.com/AikidoSec/zen-internals/releases/download", version, artifact)
  end
end

LIBZEN = [
  LibZenDL.new(:darwin, "aarch64", "libzen_internals_aarch64-apple-darwin.dylib"),
  LibZenDL.new(:darwin, "x86_64", "libzen_internals_x86_64-apple-darwin.dylib"),
  LibZenDL.new(:linux, "aarch64", "libzen_internals_aarch64-unknown-linux-gnu.so"),
  LibZenDL.new(:linux, "x86_64", "libzen_internals_x86_64-unknown-linux-gnu.so"),
  LibZenDL.new(:windows, "x86_64", "libzen_internals_x86_64-pc-windows-gnu.dll")
]
namespace :libzen do
  LIBZEN.each do |lib|
    desc "Download libzen for #{lib.os}-#{lib.arch} if necessary"
    task("#{lib.os}:#{lib.arch}" => lib.path)

    file(lib.path) {
      lib.download
      lib.verify
    }
    CLEAN.include(lib.path)
  end

  desc "Download the libzen pre-built library for all platforms"
  task "download:all" => LIBZEN.map(&:path)

  desc "Downloads the libzen library for the current platform"
  task "download:current" do
    require "rbconfig"
    os = case RbConfig::CONFIG["host_os"]
    when /darwin/ then :darwin
    when /mingw|cygwin|mswin/ then :windows
    else :linux
    end

    Rake::Task["libzen:#{os}:#{RbConfig::CONFIG["build_cpu"]}"].invoke
  end
end
