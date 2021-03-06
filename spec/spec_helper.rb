require 'bacon'
require 'mocha-on-bacon'
require 'rack/test'
require 'digest'

require 'cocoapods-core'

ENV['RACK_ENV']            = 'test'
ENV['GH_REPO']             = 'CocoaPods/Specs'
ENV['GH_USERNAME']         = 'alloy'
ENV['GH_EMAIL']            = 'bot@example.com'
ENV['GH_TOKEN']            = 'secret'
ENV['TRUNK_APP_ADMIN_PASSWORD'] = Digest::SHA2.hexdigest('secret')

$:.unshift File.expand_path('../../', __FILE__)
require 'config/init'
require 'app/controllers/app_controller'

Mocha::Configuration.prevent(:stubbing_non_existent_method)

$:.unshift(ROOT, 'spec')
Dir.glob(File.join(ROOT, 'spec/spec_helper/**/*.rb')).each do |filename|
  require File.join('spec_helper', File.basename(filename, '.rb'))
end

class Bacon::Context
  def test_controller!(app)
    extend Rack::Test::Methods
    self.singleton_class.send(:define_method, :app) { app }
  end

  def fixture(filename)
    File.join(ROOT, 'spec/fixtures', filename)
  end

  def fixture_read(filename)
    File.read(fixture(filename))
  end

  def fixture_specification(filename)
    Pod::Specification.from_file(fixture(filename))
  end

  def fixture_json(filename)
    JSON.parse(fixture_read(filename))
  end

  def fixture_response(name)
    YAML.unsafe_load(fixture_read("GitHub/#{name}.yaml"))
  end

  def fixture_new_commit_sha
    @@fixture_new_commit_sha ||= JSON.parse(fixture_response('create_new_commit').body)['commit']['sha']
  end

  alias_method :run_requirement_before_sequel, :run_requirement
  def run_requirement(description, spec)
    TRUNK_APP_LOGGER.info('-' * description.size)
    TRUNK_APP_LOGGER.info(description)
    TRUNK_APP_LOGGER.info('-' * description.size)
    Sequel::Model.db.transaction(:rollback => :always) do
      run_requirement_before_sequel(description, spec)
    end
  end
end

module Kernel
  alias_method :describe_before_controller_tests, :describe

  def describe(*description, &block)
    if description.first.is_a?(Class) && description.first.superclass == Pod::TrunkApp::AppController
      klass = description.first
      # Configure controller test and always use HTTPS
      describe_before_controller_tests(*description) do
        test_controller!(klass)
        before { header 'X-Forwarded-Proto', 'https' }
        instance_eval(&block)
      end
    else
      describe_before_controller_tests(*description, &block)
    end
  end
end

require 'net/http'
module Net
  class HTTP
    class TryingToMakeHTTPConnectionException < StandardError; end
    def connect
      raise TryingToMakeHTTPConnectionException, "Please mock your HTTP calls so you don't do any HTTP requests."
    end
  end
end

# Used in GitHub fixtures
DESTINATION_PATH = 'AFNetworking/1.2.0/AFNetworking.podspec.yaml'
MESSAGE = '[Add] AFNetworking 1.2.0'
