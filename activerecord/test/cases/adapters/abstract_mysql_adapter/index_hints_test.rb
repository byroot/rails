# frozen_string_literal: true

require "cases/helper"
require "models/post"

class IndexHintsTest < ActiveRecord::AbstractMysqlTestCase
  if supports_index_hints?
    fixtures :posts

    def test_index_hints
      assert_queries_match(%r{\ASELECT /\*\+ NO_RANGE_OPTIMIZATION\(posts index_posts_on_author_id\) \*/}) do
        posts = Post.index_hints("USE INDEX (index_posts_on_author_id)")
        p posts.explain
        assert_includes posts.explain.inspect, "index_posts_on_author_id"
      end
    end
  end
end
