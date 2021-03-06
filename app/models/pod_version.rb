require 'app/models/submission_job'

module Pod
  module TrunkApp
    class PodVersion < Sequel::Model
      DATA_URL = "https://raw.github.com/#{ENV['GH_REPO']}/%s/%s"

      self.dataset = :pod_versions
      plugin :timestamps

      many_to_one :pod
      many_to_one :published_by_submission_job, :class => 'Pod::TrunkApp::SubmissionJob'
      one_to_many :submission_jobs, :order => Sequel.asc(:id)

      alias_method :published?, :published

      def public_attributes
        { 'created_at' => created_at, 'name' => name }
      end

      def destination_path
        File.join('Specs', pod.name, name, "#{pod.name}.podspec.yaml")
      end

      def data_url
        DATA_URL % [commit_sha, destination_path] if commit_sha
      end

      def resource_path
        URI.escape("/pods/#{pod.name}/versions/#{name}")
      end
    end
  end
end
