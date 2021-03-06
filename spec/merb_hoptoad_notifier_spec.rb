require File.dirname(__FILE__) + '/spec_helper'

describe "HoptoadNotifier" do
  include Merb::Spec::Helpers

  before(:each) do
    stub(Merb).env { :production }
    stub(Merb).root { Dir.tmpdir }

    @http = Net::HTTP.new('hoptoadapp.com')
    @headers = { "Content-type" => "application/x-yaml", "Accept" => "text/xml, application/xml" }
    @config = {:development => {:api_key=>"ZOMGLOLROFLMAO"}, :production => {:api_key=>"UBERSECRETSHIT"}, :test => {:api_key=>"ZOMGLOLROFLMAO"}}
  end

  it "should define a constant" do
    HoptoadNotifier.should_not be_nil
  end

  describe ".configure" do
    before(:each) do
      mock(YAML).load_file(File.join(Merb.root / 'config' / 'hoptoad.yml')) { @config }
      HoptoadNotifier.configure
    end
    it "should know the api key after configuring" do
      HoptoadNotifier.api_key.should == 'UBERSECRETSHIT'
    end
  end

  describe ".stringify_key" do
    it "should turn string keys into symbols" do
      HoptoadNotifier.stringify_keys({'foo' => 'bar', :baz => 'foo', :bar => 'foo'}).should == { 'foo' => 'bar', 'baz' => 'foo', 'bar' => 'foo'}
    end
  end


  describe "notification" do
    before(:each) do
      stub(Net::HTTP).new('hoptoadapp.com', 80, nil, nil, nil, nil) { @http }
      mock(YAML).load_file(File.join(Merb.root / 'config' / 'hoptoad.yml')) { @config }
      HoptoadNotifier.configure
    end

    describe ".default_notice_options" do
      it "should return sane defaults" do
        HoptoadNotifier.default_notice_options.should == {
          :api_key       => HoptoadNotifier.api_key,
          :error_message => 'Notification',
          :backtrace     => nil,
          :request       => {},
          :session       => {},
          :environment   => {}
        }
      end
    end

    describe ".notify_hoptoad" do
      describe "bad input" do
        it "should handle nil input" do
          HoptoadNotifier.notify_hoptoad(nil, nil).should be_nil
        end
      end

      describe "good input" do
        before(:each) do
          mock(HoptoadNotifier).send_to_hoptoad(anything).times(2) { true }
          @request = setup_merb_request
          mock(@request).exceptions { [RuntimeError.new('ZOMG'), RuntimeError.new('ORLY')]}
          mock(@request).params { {"q"=>"0017000000SmnJ0"} }
        end
        it "should return true" do
          HoptoadNotifier.notify_hoptoad(@request, {}).should be_true
        end
      end
    end

    describe ".warn_hoptoad" do
      describe "when request is nil" do
        it "should return nil" do
          HoptoadNotifier.warn_hoptoad(nil, nil, nil).should be_nil
        end

        it "should not send anything to hoptoad" do
          dont_allow(HoptoadNotifier).send_to_hoptoad
          HoptoadNotifier.warn_hoptoad(nil, nil, nil)
        end
      end

      describe "when request is not nil" do
        before(:each) do
          mock(HoptoadNotifier).send_to_hoptoad(anything)
          @request = setup_merb_request
          mock(@request).params { {"banana_count" => "666"} }
        end
        
        it "should return true" do
          HoptoadNotifier.warn_hoptoad(nil, @request, {}).should be_true
        end

        describe "and options[:error_class] is set" do
          it "should use that for the error class instead of message" do
            RR::Space.reset_double(HoptoadNotifier, :send_to_hoptoad)
              
            # Must use satisfy here because hash_including doesn't seem to work for nested hashes
            mock(HoptoadNotifier).send_to_hoptoad(
              satisfy {|arg| arg[:notice][:error_class] == "ToasterFireException"}
            )

            HoptoadNotifier.warn_hoptoad(nil, @request, {}, :error_class => "ToasterFireException")
          end
        end

        describe "and options[:error_class] is not set" do
          it "should use message for the error class" do
            RR::Space.reset_double(HoptoadNotifier, :send_to_hoptoad)

            mock(HoptoadNotifier).send_to_hoptoad(
              satisfy {|arg| arg[:notice][:error_class] == "Out of cheese"}
            )

            HoptoadNotifier.warn_hoptoad("Out of cheese", @request, {}, {})
          end
        end
      end
    end

    describe ".send_to_hoptoad" do
      describe "any 2XX response" do
        before(:each) do
          response = Net::HTTPOK.new('1.1', 200, 'Wazzup?')
          mock(@http).post("/notices/", "--- {}\n\n", @headers) { response }
        end
        it "should log success" do
          mock(HoptoadNotifier.logger).info "Hoptoad Success: Net::HTTPOK"
          HoptoadNotifier.send_to_hoptoad({})
        end
      end
      describe "any non 2XX response" do
        before(:each) do
          response = Net::HTTPInternalServerError.new('1.1', 500, 'Upstream unavailable')
          mock(response).body { 'Upstream unavailable' }

          stub(@http.instance_variable_get('@socket')).closed? { true }
          mock(@http).post("/notices/", "--- {}\n\n", @headers) { response }
        end
        it "should log failure" do
          mock(HoptoadNotifier.logger).error "Hoptoad Failure: Net::HTTPInternalServerError\nUpstream unavailable"
          HoptoadNotifier.send_to_hoptoad({})
        end
      end
      describe "a timeout exception is thrown" do
        before(:each) do
          response = TimeoutError.new("It took too fucking long")
          mock(@http).post("/notices/", "--- {}\n\n", @headers) { raise response }
        end
        it "should log failure" do
          mock(HoptoadNotifier.logger).error("Hoptoad Failure: NilClass\n")
          mock(HoptoadNotifier.logger).error("Timeout while contacting the Hoptoad server.")
          HoptoadNotifier.send_to_hoptoad({})
        end
      end
    end
  end
end
