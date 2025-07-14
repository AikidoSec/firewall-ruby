# frozen_string_literal: true

require "ffi"
require "open-uri"
require "rubygems/package_task"

require_relative "../lib/aikido/zen/version"

class LibZen
  attr_reader :platform, :suffix, :artifact

  def initialize(platform_suffix, artifact = nil)
    platform, suffix = platform_suffix.split(".", 2)
    @platform = Gem::Platform.new(platform)
    @suffix = suffix
    @artifact = artifact
  end

  def version
    "v#{Aikido::Zen::LIBZEN_VERSION}"
  end

  def path
    "lib/aikido/zen/libzen-#{version}-#{platform}.#{suffix}"
  end

  def url
    File.join("https://github.com/AikidoSec/zen-internals/releases/download", version, artifact)
  end

  def gemspec(source = Bundler.load_gemspec("aikido-zen.gemspec"))
    return @spec if defined?(@spec)

    @spec = source.dup
    @spec.platform = platform
    @spec.files << path
    @spec
  end

  def gem_path
    "pkg/#{gemspec.name}-#{gemspec.version}-#{gemspec.platform}.gem"
  end

  def resolvable?
    downloadable? || File.exist?(path)
  end

  def downloadable?
    !artifact.nil?
  end

  def download
    puts "Downloading #{path}"
    File.open(path, "wb") { |file| FileUtils.copy_stream(URI(url).open("rb"), file) }
  end

  def verify
    expected = URI(url + ".sha256sum").read.split(/\s+/).first
    actual = Digest::SHA256.file(path).to_s

    if expected != actual
      abort "Checksum verification failed for #{path}: expected #{expected}, but got #{actual}"
    end
  end

  def namespace
    platform.to_s
  end

  def pkg_dir
    File.dirname(gem_path)
  end
end

LIBZENS = [
  LibZen.new("arm64-darwin.dylib", "libzen_internals_aarch64-apple-darwin.dylib"),
  LibZen.new("arm64-linux.so", "libzen_internals_aarch64-unknown-linux-gnu.so"),
  LibZen.new("arm64-linux-musl.so", "libzen_internals_aarch64-unknown-linux-musl.so"),
  LibZen.new("x86_64-darwin.dylib", "libzen_internals_x86_64-apple-darwin.dylib"),
  LibZen.new("x86_64-freebsd.so"),
  LibZen.new("x86_64-linux.so", "libzen_internals_x86_64-unknown-linux-gnu.so"),
  LibZen.new("x86_64-linux-musl.so", "libzen_internals_x86_64-unknown-linux-musl.so"),
  LibZen.new("x86_64-solaris.so"),
  LibZen.new("x86_64-mingw64.dll", "libzen_internals_x86_64-pc-windows-gnu.dll")
].filter(&:resolvable?)

namespace :libzen do
  LIBZENS.each do |lib|
    desc "Download libzen for #{lib.platform} if necessary"
    task(lib.namespace => lib.path)

    if lib.downloadable?
      file(lib.path) do
        lib.download
        lib.verify
      end
      CLEAN.include(lib.path)
    end

    directory lib.pkg_dir
    CLOBBER.include(lib.pkg_dir)

    file(lib.gem_path => [lib.path, lib.pkg_dir]) do
      path = Gem::Package.build(lib.gemspec)
      mv path, lib.pkg_dir
    end
    CLOBBER.include(lib.pkg_dir)

    task "#{lib.namespace}:release" => [lib.gem_path, "release:guard_clean"] do
      sh "gem", "push", lib.gem_path
    end
  end

  desc "Build all the native gems"
  task gems: LIBZENS.map(&:gem_path)

  desc "Push all the native gems to RubyGems"
  task release: LIBZENS.map { |lib| "#{lib.namespace}:release" }

  desc "Download the libzen pre-built library for all platforms"
  task "download:all" => LIBZENS.map(&:path)

  desc "Downloads the libzen library for the current platform"
  task "download:current" do
    Rake::Task["libzen:#{Gem::Platform.local}"].invoke
  end
end
