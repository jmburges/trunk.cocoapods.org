require 'sinatra/base'
require 'sinatra/twitter-bootstrap'
require 'cocoapods-core'

require 'db/config'
require 'app/models/pod'

module Pod
  module PushApp
    class ManageController < Sinatra::Base
      def self.hash_password(password)
        Digest::SHA2.hexdigest(password)
      end

      use Rack::Auth::Basic, 'Protected Area' do |username, password|
        username == 'admin' && hash_password(password) == ENV['PUSH_ADMIN_PASSWORD']
      end

      configure do
        set :root, ROOT
        set :views, settings.root + '/app/views/manage'
      end

      configure :development, :production do
        enable :logging
      end

      register Sinatra::Twitter::Bootstrap::Assets

      get '/jobs' do
        @jobs = SubmissionJob.dataset
        case params[:scope]
        when 'all'
          # no-op
        when 'failed'
          @jobs = @jobs.where(:succeeded => false)
        when 'succeeded'
          @jobs = @jobs.where(:succeeded => true)
        else
          params[:scope] = 'current'
          @jobs = @jobs.where(:succeeded => nil)
        end

        @refresh_automatically = params[:scope] == 'current'
        erb :'jobs/index'
      end

      get '/jobs/:id' do
        @job = SubmissionJob.find(:id => params[:id])
        if @job.in_progress? && params[:progress] != 'true'
          redirect to("/jobs/#{@job.id}?progress=true")
        else
          @refresh_automatically = @job.in_progress?
          erb :'jobs/show'
        end
      end
    end
  end
end