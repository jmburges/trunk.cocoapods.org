$:.unshift File.expand_path('../../../lib', __FILE__)

require 'sinatra/base'

require 'cocoapods-core/specification'
require 'cocoapods-core/specification/linter'

require 'db/config'

require 'app/models/github'
require 'app/models/owner'
require 'app/models/pod'
require 'app/models/session'
require 'app/models/travis'
require 'app/models/specification_wrapper'

module Pod
  module PushApp
    class App < Sinatra::Base
      before do
        content_type 'text/yaml'
        unless request.media_type == 'text/yaml'
          error 415, "Unable to accept input with Content-Type `#{request.media_type}`, must be `text/yaml`.".to_yaml
        end
      end

      post '/pods' do
        specification = SpecificationWrapper.from_yaml(request.body.read)

        if specification.nil?
          error 400, 'Unable to load a Pod Specification from the provided input.'.to_yaml
        end

        unless specification.valid?
          error 422, specification.validation_errors.to_yaml
        end

        resource_url = url("/pods/#{specification.name}/versions/#{specification.version}")

        # Always set the location of the resource, even when the pod version already exists.
        headers 'Location' => resource_url

        pod = Pod.find_or_create(:name => specification.name)
        # TODO use a unique index in the DB for this instead?
        if pod.versions_dataset.where(:name => specification.version).first
          error 409, "Unable to accept duplicate entry for: #{specification}".to_yaml
        end
        version = pod.add_version(:name => specification.version, :url => resource_url)
        version.add_submission_job(:specification_data => specification.to_yaml)
        halt 202
      end

      get '/pods/:name/versions/:version' do
        if pod = Pod.find(:name => params[:name])
          if version = pod.versions_dataset.where(:name => params[:version]).first
            messages = version.submission_jobs.last.log_messages.map do |log_message|
              { log_message.created_at => log_message.message }
            end
            halt(version.published? ? 200 : 102, messages.to_yaml)
          end
        end
        error 404
      end

      # TODO fix headers that are set to YAML in the before block.
      post '/travis_build_results' do
        error 401 unless Travis.authorized_webhook_notification?(env['Authorization'])

        travis = Travis.new(JSON.parse(request.body.read))
        if travis.pull_request? && job = SubmissionJob.find(:pull_request_number => travis.pull_request_number)
          job.update(:travis_build_success => travis.build_success?)
          halt 204
        end

        halt 200
      end
    end
  end
end
