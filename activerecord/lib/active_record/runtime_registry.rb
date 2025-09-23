# frozen_string_literal: true

module ActiveRecord
  # This is a thread locals registry for Active Record. For example:
  #
  #   ActiveRecord::RuntimeRegistry.sql_runtime
  #
  # returns the connection handler local to the current unit of execution (either thread of fiber).
  module RuntimeRegistry # :nodoc:
    class Stats
      attr_accessor :sql_runtime, :async_sql_runtime, :queries_count, :cached_queries_count

      def initialize
        @sql_runtime = 0.0
        @async_sql_runtime = 0.0
        @queries_count = 0
        @cached_queries_count = 0
      end

      alias_method :reset, :initialize

      def reset_runtimes
        rt, self.sql_runtime = sql_runtime, 0.0
        self.async_sql_runtime = 0.0
        rt
      end

      def reset_queries_count
        qc = queries_count
        self.queries_count = 0
        qc
      end

      def reset_cached_queries_count
        qc = cached_queries_count
        self.cached_queries_count = 0
        qc
      end
    end

    extend self

    def record(query_name, runtime, cached: false, async: false, lock_wait: nil)
      stats = self.stats

      unless query_name == "TRANSACTION" || query_name == "SCHEMA"
        stats.queries_count += 1
        stats.cached_queries_count += 1 if cached
      end

      if async
        stats.async_sql_runtime += (runtime - lock_wait)
      end
      stats.sql_runtime += runtime
    end

    def stats
      ActiveSupport::IsolatedExecutionState[:active_record_runtime] ||= Stats.new
    end

    def reset
      stats.reset
    end

    def reset_runtimes
      stats.reset_runtimes
    end

    def reset_queries_count
      stats.reset_queries_count
    end

    def reset_cached_queries_count
      stats.reset_cached_queries_count
    end
  end
end

# ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |name, start, finish, id, payload|
#   ActiveRecord::RuntimeRegistry.record(
#     payload[:name],
#     (finish - start) * 1_000.0,
#     async: payload[:async],
#     lock_wait: payload[:lock_wait],
#   )
# end
