require "puma/null_io"

# Rack::MockRequest relies on #set_encoding, which NullIO does not implement.
# Since this is only a problem in tests, we can just monkeypatch it.
unless Puma::NullIO.instance_methods.include?(:set_encoding)
  class Puma::NullIO
    def set_encoding(*)
    end
  end
end
