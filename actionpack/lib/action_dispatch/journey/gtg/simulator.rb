# frozen_string_literal: true

# :markup: markdown

require "strscan"

module ActionDispatch
  module Journey # :nodoc:
    module GTG # :nodoc:
      class MatchData # :nodoc:
        attr_reader :memos

        def initialize(memos)
          @memos = memos
        end
      end

      class Simulator # :nodoc:
        DEFAULT_EXP = /[^.\/?]+/

        STATIC_TOKENS = Array.new(64)
        STATIC_TOKENS[".".ord] = "."
        STATIC_TOKENS["/".ord] = "/"
        STATIC_TOKENS["?".ord] = "?"
        STATIC_TOKENS.freeze

        INITIAL_STATE = [ [0, nil] ].freeze

        attr_reader :tt

        def initialize(transition_table)
          @tt = transition_table
        end

        def memos(string)
          input = StringScanner.new(string)
          state = INITIAL_STATE

          until input.eos?
            start_index = input.pos

            matches_default =
              if (token = STATIC_TOKENS[string.getbyte(start_index)])
                input.pos += 1
                false
              else
                token = input.scan(DEFAULT_EXP)
              end

            state = tt.move(state, string, token, start_index, matches_default)
          end

          acceptance_states = state.each_with_object([]) do |s_d, memos|
            s, idx = s_d
            memos.concat(tt.memo(s)) if idx.nil? && tt.accepting?(s)
          end

          acceptance_states.empty? ? yield : acceptance_states
        end
      end
    end
  end
end
