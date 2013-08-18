require 'app/controllers/app_controller'

require 'app/controllers/api_controller/yaml_request_response'
require 'app/controllers/api_controller/authentication'

require 'app/models/owner'

require 'active_support/core_ext/hash/slice'

module Pod
  module TrunkApp
    module API
      class SessionsController < AppController
        helpers YAMLRequestResponse
        register Authentication

        find_authenticated_owner '/me', '/sessions'

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

        get '/me' do
          if owner?
            yaml_message(200, @owner)
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
      end
    end
  end
end
