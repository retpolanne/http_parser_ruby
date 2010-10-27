require "spec_helper"
require "json"

describe HTTP::Parser do
  before do
    @parser = HTTP::Parser.new

    @headers = nil
    @body = ""
    @started = false
    @done = false

    @parser.on_message_begin = proc{ @started = true }
    @parser.on_headers_complete = proc { |e| @headers = e }
    @parser.on_body = proc { |chunk| @body << chunk }
    @parser.on_message_complete = proc{ @done = true }
  end

  it "should have initial state" do
    @parser.headers.should be_nil

    @parser.http_version.should be_nil
    @parser.http_method.should be_nil
    @parser.status_code.should be_nil

    @parser.request_url.should be_nil
    @parser.request_path.should be_nil
    @parser.query_string.should be_nil
    @parser.fragment.should be_nil
  end

  it "should implement basic api" do
    @parser <<
      "GET /test?ok=1 HTTP/1.1\r\n" +
      "User-Agent: curl/7.18.0\r\n" +
      "Host: 0.0.0.0:5000\r\n" +
      "Accept: */*\r\n" +
      "Content-Length: 5\r\n" +
      "\r\n" +
      "World"

    @started.should be_true
    @done.should be_true

    @parser.http_major.should == 1
    @parser.http_minor.should == 1
    @parser.http_version.should == [1,1]
    @parser.http_method.should == 'GET'
    @parser.status_code.should be_nil

    @parser.request_url.should == '/test?ok=1'
    @parser.request_path.should == '/test'
    @parser.query_string.should == 'ok=1'
    @parser.fragment.should be_empty

    @parser.headers.should == @headers
    @parser.headers['User-Agent'].should == 'curl/7.18.0'
    @parser.headers['Host'].should == '0.0.0.0:5000'

    @body.should == "World"
  end

  it "should raise errors on invalid data" do
    proc{ @parser << "BLAH" }.should raise_error(HTTP::Parser::Error)
  end

  it "should abort parser via callback" do
    @parser.on_headers_complete = proc { |e| @headers = e; :stop }

    data =
      "GET / HTTP/1.0\r\n" +
      "Content-Length: 5\r\n" +
      "\r\n" +
      "World"

    bytes = @parser << data

    bytes.should == 37
    data[bytes..-1].should == 'World'

    @headers.should == {'Content-Length' => '5'}
    @body.should be_empty
    @done.should be_false
  end

  it "should reset to initial state" do
    @parser << "GET / HTTP/1.0\r\n\r\n"

    @parser.http_method.should == 'GET'
    @parser.http_version.should == [1,0]

    @parser.request_url.should == '/'
    @parser.request_path.should == '/'
    @parser.query_string.should == ''
    @parser.fragment.should == ''

    @parser.reset!.should be_true

    @parser.http_version.should be_nil
    @parser.http_method.should be_nil
    @parser.status_code.should be_nil

    @parser.request_url.should be_nil
    @parser.request_path.should be_nil
    @parser.query_string.should be_nil
    @parser.fragment.should be_nil
  end

  it "should retain callbacks after reset" do
    @parser.reset!.should be_true

    @parser << "GET / HTTP/1.0\r\n\r\n"
    @started.should be_true
    @headers.should == {}
    @done.should be_true
  end

  it "should handle multiple headers" do
    @parser <<
      "GET / HTTP/1.0\r\n" +
      "Header: value 1\r\n" +
      "Header: value 2\r\n" +
      "\r\n"

    @parser.headers.should == {
      'Header' => 'value 1, value 2'
    }
  end

  it "should support alternative api" do
    callbacks = double('callbacks')
    callbacks.stub(:on_message_begin){ @started = true }
    callbacks.stub(:on_headers_complete){ |e| @headers = e }
    callbacks.stub(:on_body){ |chunk| @body << chunk }
    callbacks.stub(:on_message_complete){ @done = true }

    @parser = HTTP::Parser.new(callbacks)
    @parser << "GET / HTTP/1.0\r\n\r\n"

    @started.should be_true
    @headers.should == {}
    @body.should == ''
    @done.should be_true
  end

  %w[ request response ].each do |type|
    JSON.parse(File.read(File.expand_path("../support/#{type}s.json", __FILE__))).each do |test|
      test['headers'] ||= {}

      it "should parse #{type}: #{test['name']}" do
        @parser << test['raw']

        @parser.keep_alive?.should == test['should_keep_alive']
        @parser.upgrade?.should == (test['upgrade']==1)
        @parser.http_method.should == test['method']

        fields = %w[
          http_major
          http_minor
        ]

        if test['type'] == 'HTTP_REQUEST'
          fields += %w[
            request_url
            request_path
            query_string
            fragment
          ]
        else
          fields += %w[
            status_code
          ]
        end

        fields.each do |field|
          @parser.send(field).should == test[field]
        end

        @headers.size.should == test['num_headers']
        @headers.should == test['headers']

        @body.should == test['body']
        @body.size.should == test['body_size'] if test['body_size']
      end
    end
  end
end