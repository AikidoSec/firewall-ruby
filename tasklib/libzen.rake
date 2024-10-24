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

  def gem_path
    platform = "-#{gemspec.platform}" unless gemspec.platform.to_s == "ruby"
    "pkg/#{gemspec.name}-#{gemspec.version}#{platform}.gem"
  end

  def pkg_dir
    File.dirname(gem_path)
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

  def gem_platform
    gem_os = (os == :windows) ? "mingw64" : os
    platform = (arch == "aarch64") ? "arm64" : arch
    Gem::Platform.new("#{platform}-#{gem_os}")
  end

  def gemspec(source = Bundler.load_gemspec("aikido-zen.gemspec"))
    return @spec if defined?(@spec)

    @spec = source.dup
    @spec.platform = gem_platform
    @spec.files << path
    @spec
  end

  def namespace
    "#{os}:#{arch}"
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
    task(lib.namespace => lib.path)

    file(lib.path) {
      lib.download
      lib.verify
    }
    CLEAN.include(lib.path)

    directory lib.pkg_dir
    CLOBBER.include(lib.pkg_dir)

    file(lib.gem_path => [lib.path, lib.pkg_dir]) {
      path = Gem::Package.build(lib.gemspec)
      mv path, lib.pkg_dir
    }
    CLOBBER.include(lib.pkg_dir)

    task "#{lib.namespace}:release" => [lib.gem_path, "release:guard_clean"] do
      sh "gem", "push", lib.gem_path
    end
  end

  desc "Build all the native gems for the different libzen versions"
  task gems: LIBZEN.map(&:gem_path)

  desc "Push all the native gems to RubyGems"
  task release: LIBZEN.map { |lib| "#{lib.namespace}:release" }

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
