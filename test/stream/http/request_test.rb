# encoding: UTF-8

require 'vines'
require 'minitest/autorun'

class RequestTest < MiniTest::Unit::TestCase
  PASSWORD = File.expand_path('../passwords')
  INDEX    = File.expand_path('index.html')

  def setup
    File.open(PASSWORD, 'w') {|f| f.puts '/etc/passwd contents' }
    File.open(INDEX, 'w') {|f| f.puts 'index.html contents' }

    @stream = MiniTest::Mock.new
    @parser = MiniTest::Mock.new
    @parser.expect(:headers, {'Content-Type' => 'text/html', 'Host' => 'wonderland.lit'})
    @parser.expect(:http_method, 'GET')
    @parser.expect(:request_path, '/blogs/12')
    @parser.expect(:request_url, '/blogs/12?ok=true')
    @parser.expect(:query_string, 'ok=true')
  end

  def teardown
    File.delete(PASSWORD)
    File.delete(INDEX)
  end

  def test_copies_request_info_from_parser
    request = Vines::Stream::Http::Request.new(@stream, @parser, '<html></html>')
    assert_equal request.headers, {'Content-Type' => 'text/html', 'Host' => 'wonderland.lit'}
    assert_equal request.method, 'GET'
    assert_equal request.path, '/blogs/12'
    assert_equal request.url, '/blogs/12?ok=true'
    assert_equal request.query, 'ok=true'
    assert_equal request.body, '<html></html>'
    assert @stream.verify
    assert @parser.verify
  end

  def test_reply_with_file_404
    request = Vines::Stream::Http::Request.new(@stream, @parser, '<html></html>')

    headers = [
      "HTTP/1.1 404 Not Found",
      "Content-Length: 0"
    ].join("\r\n")

    @stream.expect(:stream_write, nil, ["#{headers}\r\n\r\n"])

    request.reply_with_file(Dir.pwd)
    assert @stream.verify
    assert @parser.verify
  end

  def test_reply_with_file_directory_traversal
    parser = MiniTest::Mock.new
    parser.expect(:headers, {'Content-Type' => 'text/html', 'Host' => 'wonderland.lit'})
    parser.expect(:http_method, 'GET')
    parser.expect(:request_path, '/../passwords')
    parser.expect(:request_url, '/../passwords')
    parser.expect(:query_string, '')

    request = Vines::Stream::Http::Request.new(@stream, parser, '<html></html>')

    headers = [
      "HTTP/1.1 404 Not Found",
      "Content-Length: 0"
    ].join("\r\n")

    @stream.expect(:stream_write, nil, ["#{headers}\r\n\r\n"])

    request.reply_with_file(Dir.pwd)
    assert @stream.verify
    assert parser.verify
  end

  def test_reply_with_file_for_directory_serves_index_html
    parser = MiniTest::Mock.new
    parser.expect(:headers, {'Content-Type' => 'text/html', 'Host' => 'wonderland.lit'})
    parser.expect(:http_method, 'GET')
    parser.expect(:request_path, '/')
    parser.expect(:request_url, '/?ok=true')
    parser.expect(:query_string, 'ok=true')

    request = Vines::Stream::Http::Request.new(@stream, parser, '<html></html>')

    mtime = File.mtime(INDEX).utc.strftime('%a, %d %b %Y %H:%M:%S GMT')
    headers = [
      "HTTP/1.1 200 OK",
      'Content-Type: text/html; charset="utf-8"',
      "Content-Length: 20",
      "Last-Modified: #{mtime}"
    ].join("\r\n")

    @stream.expect(:stream_write, nil, ["#{headers}\r\n\r\n"])
    @stream.expect(:stream_write, nil, ["index.html contents\n"])

    request.reply_with_file(Dir.pwd)
    assert @stream.verify
    assert parser.verify
  end

  def test_reply_with_file_redirects_for_missing_slash
    parser = MiniTest::Mock.new
    parser.expect(:headers, {'Content-Type' => 'text/html', 'Host' => 'wonderland.lit'})
    parser.expect(:http_method, 'GET')
    parser.expect(:request_path, '/http')
    parser.expect(:request_url, '/http?ok=true')
    parser.expect(:query_string, 'ok=true')

    request = Vines::Stream::Http::Request.new(@stream, parser, '<html></html>')

    headers = [
      "HTTP/1.1 301 Moved Permanently",
      "Content-Length: 0",
      "Location: http://wonderland.lit/http/?ok=true"
    ].join("\r\n")

    @stream.expect(:stream_write, nil, ["#{headers}\r\n\r\n"])
    # so the /http url above will work
    request.reply_with_file(File.expand_path('../../', __FILE__))
    assert @stream.verify
    assert parser.verify
  end

  def test_reply_to_options
    parser = MiniTest::Mock.new
    parser.expect(:headers, {
      'Content-Type' => 'text/xml',
      'Host' => 'wonderland.lit',
      'Origin' => 'remote.wonderland.lit',
      'Access-Control-Request-Headers' => 'Content-Type, Origin'})
    parser.expect(:http_method, 'OPTIONS')
    parser.expect(:request_path, '/xmpp')
    parser.expect(:request_url, '/xmpp')
    parser.expect(:query_string, '')

    request = Vines::Stream::Http::Request.new(@stream, parser, '')

    headers = [
      "HTTP/1.1 200 OK",
      "Content-Length: 0",
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Methods: POST, GET, OPTIONS",
      "Access-Control-Allow-Headers: Content-Type, Origin",
      "Access-Control-Max-Age: 2592000"
    ].join("\r\n")

    @stream.expect(:stream_write, nil, ["#{headers}\r\n\r\n"])
    request.reply_to_options
    assert @stream.verify
    assert parser.verify
  end

  def test_reply
    parser = MiniTest::Mock.new
    parser.expect(:headers, {
      'Content-Type' => 'text/xml',
      'Host' => 'wonderland.lit',
      'Origin' => 'remote.wonderland.lit'})
    parser.expect(:http_method, 'POST')
    parser.expect(:request_path, '/xmpp')
    parser.expect(:request_url, '/xmpp')
    parser.expect(:query_string, '')

    request = Vines::Stream::Http::Request.new(@stream, parser, '')
    message = '<message>hello</message>'

    headers = [
      "HTTP/1.1 200 OK",
      "Access-Control-Allow-Origin: *",
      "Content-Type: application/xml",
      "Content-Length: 24"
    ].join("\r\n")

    @stream.expect(:stream_write, nil, ["#{headers}\r\n\r\n#{message}"])
    request.reply(message, 'application/xml')
    assert @stream.verify
    assert parser.verify
  end
end
