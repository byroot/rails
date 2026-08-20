# frozen_string_literal: true

require "json"

module ActiveRecord
  module ConnectionAdapters
    class JSONSchemaCacheSerializer
      REGISTRY = {
        "column"            => "ActiveRecord::ConnectionAdapters::Column",
        "index"             => "ActiveRecord::ConnectionAdapters::IndexDefinition",
        "schema_cache"      => "ActiveRecord::ConnectionAdapters::SchemaCache",
        "sql_type_metadata" => "ActiveRecord::ConnectionAdapters::SqlTypeMetadata",

        "date"                  => "ActiveRecord::Type::Date",
        "datetime"              => "ActiveRecord::Type::DateTime",
        "decimal_without_scale" => "ActiveRecord::Type::DecimalWithoutScale",
        "json"                  => "ActiveRecord::Type::Json",
        "text"                  => "ActiveRecord::Type::Text",
        "time"                  => "ActiveRecord::Type::Time",
        "unsigned_integer"      => "ActiveRecord::Type::UnsignedInteger",

        "binary"  => "ActiveModel::Type::Binary",
        "boolean" => "ActiveModel::Type::Boolean",
        "decimal" => "ActiveModel::Type::Decimal",
        "float"   => "ActiveModel::Type::Float",
        "integer" => "ActiveModel::Type::Integer",
        "string"  => "ActiveModel::Type::String",
        "value"   => "ActiveModel::Type::Value",

        "mysql_column"           => "ActiveRecord::ConnectionAdapters::MySQL::Column",
        "mysql_index_definition" => "ActiveRecord::ConnectionAdapters::MySQL::IndexDefinition",
        "mysql_type_metadata"    => "ActiveRecord::ConnectionAdapters::MySQL::TypeMetadata",

        "sqlite3_column"  => "ActiveRecord::ConnectionAdapters::SQLite3::Column",
        "sqlite3_integer" => "ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer",

        "postgresql_column"        => "ActiveRecord::ConnectionAdapters::PostgreSQL::Column",
        "postgresql_type_metadata" => "ActiveRecord::ConnectionAdapters::PostgreSQL::TypeMetadata",

        "postgresql_array"                    => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array",
        "postgresql_bit"                      => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Bit",
        "postgresql_bit_varying"              => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::BitVarying",
        "postgresql_bytea"                    => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Bytea",
        "postgresql_cidr"                     => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Cidr",
        "postgresql_date"                     => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Date",
        "postgresql_date_time"                => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::DateTime",
        "postgresql_decimal"                  => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Decimal",
        "postgresql_enum"                     => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Enum",
        "postgresql_hstore"                   => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Hstore",
        "postgresql_inet"                     => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Inet",
        "postgresql_interval"                 => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Interval",
        "postgresql_jsonb"                    => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb",
        "postgresql_legacy_point"             => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::LegacyPoint",
        "postgresql_macaddr"                  => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Macaddr",
        "postgresql_money"                    => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Money",
        "postgresql_point"                    => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Point",
        "postgresql_range"                    => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Range",
        "postgresql_specialized_string"       => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::SpecializedString",
        "postgresql_timestamp"                => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Timestamp",
        "postgresql_timestamp_with_time_zone" => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::TimestampWithTimeZone",
        "postgresql_uuid"                     => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Uuid",
        "postgresql_vector"                   => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Vector",
        "postgresql_xml"                      => "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Xml",
      }.freeze

      @class_registry = {}
      @type_registry = REGISTRY.invert

      loading_proc = ->(object) do
        if object.is_a?(Hash) && object.key?("_type")
          case object["_type"]
            when "big_decimal" then BigDecimal(object["value"])
            when "date_value" then ::Date.iso8601(object["value"])
            when "time_value" then ::Time.iso8601(object["value"])
            else
              klass = class_for(object["_type"])
              instance = klass.allocate
              instance.init_from_schema_json(object)
              instance
          end
        else
          object
        end
      end



      CODER = JSON::Coder.new(on_load: loading_proc) do |object, is_key|
        if object.respond_to?(:as_schema_json)
          data = object.as_schema_json
          data.compact!
          data["_type"] = type_for(object.class)
          data
        else
          case object
          when BigDecimal then { "_type" => "big_decimal", "value" => object.to_s("F") }
          when ::Date then { "_type" => "date_value", "value" => object.iso8601 }
          when ::Time then { "_type" => "time_value", "value" => object.iso8601(9) }
          else
            raise ArgumentError, "Cannot serialize #{object.class} to JSON schema cache"
          end
        end
      end

      class << self
        def register(type, klass)
          @class_registry[type] = klass
          @type_registry[klass.name] = type
        end

        def class_for(type)
          @class_registry[type] ||= Object.const_get(REGISTRY.fetch(type))
        end

        def type_for(klass)
          @type_registry.fetch(klass.name)
        end

        def dump(cache)
          objects = {}.compare_by_identity
          references = []
          count = -1
          coder = JSON::Coder.new(indent: "  ", space: " ", object_nl: "\n", array_nl: "\n") do |object, is_key|
            if object.respond_to?(:as_schema_json)
              unless object_id = objects[object]  
                object_id = objects[object] = (count += 1)
                data = object.as_schema_json
                data.compact!
                data["_type"] = type_for(object.class)
                references[object_id] = coder.dump(data)
              end

              object_id
            else
              case object
              when BigDecimal then { "_type" => "big_decimal", "value" => object.to_s("F") }
              when ::Date then { "_type" => "date_value", "value" => object.iso8601 }
              when ::Time then { "_type" => "time_value", "value" => object.iso8601(9) }
              else
                raise ArgumentError, "Cannot serialize #{object.class} to JSON schema cache"
              end
            end
          end
          result = coder.dump(cache)
          schema = JSON.dump(references.map { |d| JSON::Fragment.new(d) })

          puts schema
          schema
        end

        class ReferenceList
          def initialize(references)
            @references = references
          end

          def [](index)
            entry = @references[index]
            if entry.is_a?(Hash)
              entry = @references[index] = load_reference(entry)
            end
            entry
          end

          def load_reference(object)
            klass = JSONSchemaCacheSerializer.class_for(object.fetch("_type"))
            instance = klass.allocate
            instance.init_from_schema_json(object, self)
            instance
          end
        end

        def load(data)
          references = ReferenceList.new(JSON.load(data))
          references[0]
        end
      end
    end
  end
end
