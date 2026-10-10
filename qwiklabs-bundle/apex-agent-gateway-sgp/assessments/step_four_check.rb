require 'net/http'
require 'json'
require 'uri'

def step_four_check(handles:, maximum_score:, resources:)
  ret_hash = { :done => false, :score => 0, :message => "", :student_message => "" }

  begin
    logging = handles['project_0.LoggingV2']
    project_id = (resources.dig('project_0', 'project_id') rescue nil) ||
                 (resources['project_0.project_id'] rescue nil) ||
                 (logging.project rescue nil)

    sgp_found = false
    if logging && project_id
      ['us-central1', 'us-east1', 'us-west1', 'europe-west1', 'europe-west4'].each do |loc|
        break if sgp_found
        begin
          uri = URI("https://#{loc}-aiplatform.googleapis.com/v1beta1/projects/#{project_id}/locations/#{loc}/semanticGovernancePolicies")
          req = Net::HTTP::Get.new(uri)
          logging.authorization.apply!(req)
          resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
          if resp.is_a?(Net::HTTPSuccess) && resp.body.include?('high-value-limit')
            sgp_found = true
          end
        rescue
          nil
        end
      end
    end

    if !sgp_found && logging && project_id
      begin
        lab_start_time = Time.at(Time.now.to_i - 86400)
        log_filters = [
          'timestamp>"' + lab_start_time.utc.iso8601 + '"',
          '(logName="projects/' + project_id + '/logs/semantic-governance-policy" OR protoPayload.resourceName:"high-value-limit" OR protoPayload.resourceName:"agent-egress-sgp-authzpolicy")'
        ]
        req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
        req.resource_names = ['projects/' + project_id]
        req.filter = log_filters.join(" AND ")
        query_logs = logging.list_entry_log_entries(req)&.entries || []
        sgp_found = true if query_logs.count > 0
      rescue
        nil
      end
    end

    if sgp_found
      ret_hash = {
        :done => true,
        :score => maximum_score,
        :message => 'success',
        :student_message => 'success'
      }
    else
      ret_hash[:message] = 'sgp_missing'
      ret_hash[:student_message] = 'sgp_missing'
    end
  rescue => e
    ret_hash[:message] = e.message
    ret_hash[:student_message] = 'sgp_missing'
  end

  return ret_hash
end
