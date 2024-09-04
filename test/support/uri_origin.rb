# frozen_string_literal: true

# Backports URI#authority and URI#origin for ruby versions < 3.1
class URI::HTTP < URI::Generic
  unless instance_methods.include?(:authority)
    def authority
      if port == default_port
        host
      else
        "#{host}:#{port}"
      end
    end
  end

  unless instance_methods.include?(:origin)
    def origin
      "#{scheme}://#{authority}"
    end
  end
end
