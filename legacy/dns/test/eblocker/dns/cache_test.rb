require 'minitest/autorun'
require 'bundler/setup'
require 'eblocker/dns/cache'

class CacheCompatibilityTest < Minitest::Test
  def test_cached_answer_expires_at_its_ttl
    now = Time.now
    cache = Cache.new(2)
    cache.put('example.test', :answer, 60, now)
    assert_equal :answer, cache.get('example.test', now + 30)
    assert_nil cache.get('example.test', now + 61)
    assert_equal 0, cache.size
  end

  def test_capacity_evicts_the_least_recently_used_answer
    now = Time.now
    cache = Cache.new(2)
    cache.put('first', :first, 60, now)
    cache.put('second', :second, 60, now)
    cache.get('first', now)
    cache.put('third', :third, 60, now)
    assert_equal :first, cache.get('first', now)
    assert_nil cache.get('second', now)
    assert_equal :third, cache.get('third', now)
  end
end
