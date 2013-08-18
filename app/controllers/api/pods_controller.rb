require 'app/controllers/api_controller'
require 'app/models/owner'
require 'app/models/pod'
require 'app/models/specification_wrapper'

module Pod
  module TrunkApp
    module API
      class PodsController < AppController
        helpers YAMLRequestResponse
        register Authentication

        find_authenticated_owner '/pods'

        post '/pods' do
          if owner?
            specification = SpecificationWrapper.from_yaml(request.body.read)

            if specification.nil?
              yaml_error(400, 'Unable to load a Pod Specification from the provided input.')
            end

            unless specification.valid?
              yaml_error(422, specification.validation_errors)
            end

            resource_url = url("/pods/#{specification.name}/versions/#{specification.version}")

            # Always set the location of the resource, even when the pod version already exists.
            headers 'Location' => resource_url

            pod = Pod.find_or_create(:name => specification.name)
            # TODO use a unique index in the DB for this instead?
            if pod.versions_dataset.where(:name => specification.version).first
              yaml_error(409, "Unable to accept duplicate entry for: #{specification}")
            end
            version = pod.add_version(:name => specification.version, :url => resource_url)
            version.add_submission_job(:specification_data => specification.to_yaml)
            halt 202
          end
        end

        get '/pods/:name/versions/:version' do
          if pod = Pod.find(:name => params[:name])
            if version = pod.versions_dataset.where(:name => params[:version]).first
              job = version.submission_jobs.last
              messages = job.log_messages.map do |log_message|
                { log_message.created_at => log_message.message }
              end
              # Would have preferred to use 102 instead of 202, but Ruby’s Net::HTTP apperantly does
              # not read the body of a 102 and so the client might have problems reporting status.
              status = job.failed? ? 404 : (version.published? ? 200 : 202)
              yaml_message(status, messages)
            end
          end
          error 404
        end
      end
    end
  end
end
