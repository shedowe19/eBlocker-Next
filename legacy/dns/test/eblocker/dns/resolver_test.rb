require 'minitest/autorun'
require 'bundler/setup'
require 'eblocker/dns/version'
require 'eblocker/dns/server'

class ResolverCompatibilityTest < Minitest::Test
  class RecordingResolver < Eblocker::Dns::Server::Resolver
    attr_reader :request_options

    def dispatch_request(message, options)
      @request_options = options
      nil
    end
  end

  def setup
    @nameservers = [[:udp, '127.0.0.1', 15353], [:udp, '127.0.0.1', 15354]]
  end

  def test_ruby3_keyword_constructor_and_fork_round_robin
    resolver = Eblocker::Dns::Server::Resolver.new(@nameservers, {}, nil)
    assert_equal 3, resolver.instance_variable_get(:@timeout)
    assert_equal @nameservers, resolver.send(:servers_ordered, :round_robin)
    assert_equal @nameservers.rotate(1), resolver.send(:servers_ordered, :round_robin)
  end

  def test_query_keeps_fork_order_bind_address_and_request_log
    resolver = RecordingResolver.new(@nameservers, {order: :round_robin}, nil)
    resolver.query('example.test.', Resolv::DNS::Resource::IN::A, {bind_host: '127.0.0.1'})
    assert_equal :round_robin, resolver.request_options[:order]
    assert_equal '127.0.0.1', resolver.request_options[:bind_host]
    assert_same resolver.instance_variable_get(:@log), resolver.request_options[:log]
  end
end
