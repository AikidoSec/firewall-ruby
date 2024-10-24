# frozen_string_literal: true

require_relative "lib/aikido/zen/version"

Gem::Specification.new do |spec|
  spec.name = "aikido-zen"
  spec.version = Aikido::Zen::VERSION
  spec.authors = ["Nicolas Sanguinetti"]
  spec.email = ["foca@foca.io"]
  spec.license = "AGPL-3.0-or-later"

  spec.summary = "Embedded Web Application Firewall that autonomously protects Ruby apps against common and critical attacks."
  spec.homepage = "https://aikido.dev"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/aikidosec/firewall-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/aikidosec/firewall-ruby/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ sample_apps/ .git .github appveyor Gemfile gemfiles/])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "rack"
  spec.add_dependency "ffi"
end
