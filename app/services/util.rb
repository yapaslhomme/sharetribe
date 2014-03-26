module Util
  module HashUtils
    module_function

    def compact(h)
      h.delete_if { |k, v| v.nil? }
    end

    def camelize_keys(h)
      h.inject({}) { |memo, (k, v)| 
        memo[k.to_s.camelize(:lower).to_sym] = v.is_a?(Hash) ? camelize_keys(v) : v
        memo
      }
    end
  end
end