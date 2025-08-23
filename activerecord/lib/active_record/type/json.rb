# frozen_string_literal: true

require "active_support/json"

module ActiveRecord
  module Type
    class Json < ActiveModel::Type::Value
      include ActiveModel::Type::Helpers::Mutable

      def type
        :json
      end

      def changed?(old_attribute, new_value, new_value_before_type_cast)
        if old_attribute.has_been_read?
          old_attribute.original_value != new_value
        else
          old_attribute.value_before_type_cast != new_value_before_type_cast
        end
      end

      def deserialize(value)
        return value unless value.is_a?(::String)
        ActiveSupport::JSON.decode(value) #rescue nil
      end

      JSON_ENCODER = ActiveSupport::JSON::Encoding.json_encoder.new(escape: false)

      def serialize(value)
        JSON_ENCODER.encode(value) unless value.nil?
      end

      def changed_in_place?(raw_old_value, new_value)
        deserialize(raw_old_value) != new_value
      end

      def accessor
        ActiveRecord::Store::StringKeyedHashAccessor
      end
    end
  end
end
