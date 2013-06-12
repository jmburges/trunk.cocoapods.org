require File.expand_path('../../spec_helper', __FILE__)

module Fixtures
  # Taken from https://github.com/dtao/safe_yaml/blob/master/README.md#explanation
  class ClassBuilder
    def self.this_should_not_be_called!
    end

    def []=(key, value)
      self.class.class_eval <<-EOS
        def #{key}
          #{value}
        end
      EOS
    end
  end
end

module Pod::PushApp
  describe "App" do
    extend Rack::Test::Methods
    extend SpecHelpers::App

    def spec
      @spec ||= fixture_specification('AFNetworking.podspec')
    end

    before do
      @spec = nil
      header 'Content-Type', 'text/yaml'
    end

    it "only accepts YAML" do
      header 'Content-Type', 'application/json'
      post '/pods'
      last_response.status.should == 415
    end

    it "does not allow unsafe YAML to load" do
      yaml = <<-EOYAML
--- !ruby/hash:Fixtures::ClassBuilder
"foo; end; this_should_not_be_called!; def bar": "baz"
EOYAML
      Fixtures::ClassBuilder.expects(:this_should_not_be_called!).never
      post '/pods', yaml
    end

    it "fails with data other than serialized spec data" do
      lambda {
        post '/pods', ''
      }.should.not.change { Pod.count + PodVersion.count }
      last_response.status.should == 400

      lambda {
        post '/pods', "---\nsomething: else\n"
      }.should.not.change { Pod.count + PodVersion.count }
      last_response.status.should == 422
    end

    it "fails with a spec that does not pass a quick lint" do
      spec.name = nil
      spec.version = nil
      spec.license = nil

      lambda {
        post '/pods', spec.to_yaml
      }.should.not.change { Pod.count + PodVersion.count }

      last_response.status.should == 422
      YAML.load(last_response.body).should == {
        'errors'   => ['Missing required attribute `name`.', 'The version of the spec should be higher than 0.'],
        'warnings' => ['Missing required attribute `license`.', 'Missing license type.']
      }
    end

    it "creates new pod and version records" do
      lambda {
        lambda {
          post '/pods', spec.to_yaml
        }.should.change { Pod.count }
      }.should.change { PodVersion.count }
      last_response.status.should == 202
      last_response.location.should == 'http://example.org/pods/AFNetworking/versions/1.2.0'
      Pod.first(:name => spec.name).versions.map(&:name).should == [spec.version.to_s]
    end

    it "does not allow a push for an existing pod version" do
      Pod.create(:name => spec.name).add_version(:name => spec.version.to_s)
      lambda {
        post '/pods', spec.to_yaml
      }.should.not.change { Pod.count + PodVersion.count }
      last_response.status.should == 409
      last_response.location.should == 'http://example.org/pods/AFNetworking/versions/1.2.0'
    end

    it "creates a submission job and log message once a new pod version is created" do
      post '/pods', spec.to_yaml
      job = Pod.first(:name => spec.name).versions.first.submission_jobs.last
      job.specification_data.should == spec.to_yaml
      job.log_messages.map(&:message).should == ['Submitted']
    end

    before do
      @version = Pod.create(:name => spec.name).add_version(:name => spec.version.to_s)
      @job = @version.add_submission_job(:specification_data => spec.to_yaml, :pull_request_number => 3)
    end

    it "returns the status of the submission flow" do
      @job.add_log_message(:message => 'Another message')
      get '/pods/AFNetworking/versions/1.2.0'
      last_response.body.should == @job.log_messages.map do |log_message|
        { log_message.created_at => log_message.message }
      end.to_yaml
    end

    it "returns that the pod version is not yet published" do
      get '/pods/AFNetworking/versions/1.2.0'
      last_response.status.should == 102
    end

    it "returns that the pod version is published" do
      @version.update(:published => true)
      get '/pods/AFNetworking/versions/1.2.0'
      last_response.status.should == 200
    end

    it "returns a 404 when a pod or version can't be found" do
      get '/pods/AFNetworking/versions/0.2.1'
      last_response.status.should == 404
      get '/pods/FANetworking/versions/1.2.0'
      last_response.status.should == 404
    end

    before do
      @job.update(:state => 'pull-request-submitted')
    end

    it "does not allow updates to submission job's if the client isn't authorized" do
      post '/travis_build_results', fixture_read('TravisCI/pull-request_success_payload.json'), { 'Authorization' => 'incorrect token' }
      last_response.status.should == 401
      @job.reload.travis_build_success?.should == nil
      @job.should.be.pull_request_submitted
    end

    it "does not break with a normal commit Travis build status notification" do
      post '/travis_build_results', fixture_read('TravisCI/commit_payload.json'), { 'Authorization' => Travis.webhook_authorization_token }
      last_response.status.should == 200
      @job.reload.travis_build_success?.should == nil
      @job.should.be.pull_request_submitted
    end

    it "does not break with a Travis build status notification for an unknown pull-request" do
      post '/travis_build_results', fixture_read('TravisCI/pull-request_unknown_payload.json'), { 'Authorization' => Travis.webhook_authorization_token }
      last_response.status.should == 200
      @job.reload.travis_build_success?.should == nil
      @job.should.be.pull_request_submitted
    end

    it "updates the submission job's Travis build status as passing the lint process" do
      post '/travis_build_results', fixture_read('TravisCI/pull-request_success_payload.json'), { 'Authorization' => Travis.webhook_authorization_token }
      last_response.status.should == 204
      @job.reload.travis_build_success?.should == true
      @job.should.be.travis_notification_received
    end

    it "updates the submission job's Travis build status as failing the lint process" do
      post '/travis_build_results', fixture_read('TravisCI/pull-request_failure_payload.json'), { 'Authorization' => Travis.webhook_authorization_token }
      last_response.status.should == 204
      @job.reload.travis_build_success?.should == false
      @job.should.be.travis_notification_received
    end
  end
end

module Pod::PushApp
  describe "App" do
    before do
      @email = 'jenny@example.com'
    end

    describe "an unauthenticated consumer, which is not known to the system" do
      extend Rack::Test::Methods
      extend SpecHelpers::App
      extend SpecHelpers::Response

      before do
        header 'Content-Type', 'text/yaml'
      end

      it "sees a useful error message when posting blank owner data" do
        post '/register'
        last_response.status.should == 422
        yaml = yaml_response
        yaml.keys.should == %w(error)
        yaml['error'].should == "Please send the owner email address in the body of your post."
      end

      it "creates a new session" do
        post '/register', { 'email' => @email }.to_yaml
        last_response.status.should == 201
        yaml_response['email'].should == @email
      end
    end
  end
end

