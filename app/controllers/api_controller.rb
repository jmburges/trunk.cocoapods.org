require 'app/controllers/app_controller'

require 'app/models/owner'
require 'app/models/pod'
require 'app/models/session'
require 'app/models/specification_wrapper'

require 'active_support/core_ext/hash/slice'

module Pod
  module TrunkApp
    class APIController < AppController
      require 'app/controllers/api_controller/yaml_request_response'
      require 'app/controllers/api_controller/authentication'

      find_authenticated_owner '/me', '/sessions', '/pods', '/pods/:name/owners'

      # --- Sessions ------------------------------------------------------------------------------

      get '/me' do
        if owner?
          yaml_message(200, @owner)
        end
      end

      post '/register' do
        owner_params = YAML.load(request.body.read)
        if !owner_params.kind_of?(Hash) || owner_params.empty?
          yaml_error(422, 'Please send the owner email address in the body of your post.')
        else
          owner = Owner.find_by_email(owner_params['email']) || Owner.create(owner_params.slice('email', 'name'))
          session = owner.create_session!(url('/sessions/verify/%s'))
          yaml_message(201, session)
        end
      end

      # TODO render HTML
      get '/sessions/verify/:token' do
        if session = Session.with_verification_token(params[:token])
          session.update(:verified => true)
          yaml_message(200, session)
        else
          yaml_error(404, 'Session not found.')
        end
      end

      get '/sessions' do
        if owner?
          yaml_message(200, @owner.sessions.map(&:public_attributes))
        end
      end

      delete '/sessions' do
        if owner?
          @owner.sessions.each do |session|
            session.destroy unless session == @session
          end
          yaml_message(200, @session)
        end
      end

      # --- Pods ----------------------------------------------------------------------------------

      get '/pods/:name' do
        if pod = Pod.find(:name => params[:name])
          versions = pod.versions_dataset.where(:published => true).to_a
          unless versions.empty?
            yaml_message(200, 'versions' => versions.map(&:public_attributes),
                              'owners'   => pod.owners.map(&:public_attributes))
          end
        end
        yaml_error(404, 'No pod found with the specified name.')
      end

      get '/pods/:name/versions/:version' do
        if pod = Pod.find(:name => params[:name])
          if version = pod.versions_dataset.where(:name => params[:version]).first
            if version.published?
              job = version.submission_jobs.last
              yaml_message(200, 'messages' => job.log_messages.map(&:public_attributes),
                                'data_url' => version.data_url)
            end
          end
        end
        yaml_error(404, 'No pod found with the specified version.')
      end

      post '/pods' do
        if owner?
          specification = SpecificationWrapper.from_yaml(request.body.read)
          if specification.nil?
            yaml_error(400, 'Unable to load a Pod Specification from the provided input.')
          end
          unless specification.valid?
            yaml_error(422, specification.validation_errors)
          end

          pod = Pod.find_by_name_and_owner(specification.name, @owner) do
            yaml_error(403, 'You are not allowed to push new versions for this pod.')
          end
          unless pod
            pod = Pod.create(:name => specification.name)
          end

          # TODO use a unique index in the DB for this instead?
          if version = pod.versions_dataset.where(:name => specification.version).first
            if version.published? || version.submission_jobs_dataset.where(:succeeded => nil).first
              headers 'Location' => url(version.resource_path)
              yaml_error(409, "Unable to accept duplicate entry for: #{specification}")
            end
          else
            version = pod.add_version(:name => specification.version)
          end

          job = version.add_submission_job(:specification_data => specification.to_yaml, :owner => @owner)
          if job.submit_specification_data!
            redirect url(version.resource_path)
          else
            yaml_error(500, 'Failed to publish. In case this keeps failing, please open a ticket ' \
                            'including the name and version at https://github.com/CocoaPods/Specs/issues/new.')
          end
        end
      end

      patch '/pods/:name/owners' do
        if owner?
          pod = Pod.find_by_name_and_owner(params[:name], @owner) do
            yaml_error(403, 'You are not allowed to add owners to this pod.')
          end
          unless pod
            yaml_error(404, 'No pod found with the specified name.')
          end

          owner_params = YAML.load(request.body.read)
          if !owner_params.kind_of?(Hash) || owner_params.empty?
            yaml_error(422, 'Please send the owner email address in the body of your post.')
          end

          unless other_owner = Owner.find_by_email(owner_params['email'])
            yaml_error(404, 'No owner found with the specified email address.')
          end

          pod.add_owner(other_owner)
          yaml_message(200, pod.owners.map(&:public_attributes))
        end
      end
    end
  end
end
