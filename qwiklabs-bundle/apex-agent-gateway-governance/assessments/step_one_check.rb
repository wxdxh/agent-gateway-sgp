require 'net/http'
require 'json'
require 'uri'

def step_one_check(handles:, maximum_score:, resources:)
  ret_hash = { :done => false, :score => 0, :message => "", :student_message => "" }

  begin
    compute = handles['project_0.ComputeV1']
    logging = handles['project_0.LoggingV2']
    auth_handle = logging || compute
    project_id = (resources.dig('project_0', 'project_id') rescue nil) ||
                 (resources['project_0.project_id'] rescue nil) ||
                 (logging.project rescue nil) ||
                 (compute.project rescue nil)

    agw_found = false
    if auth_handle && project_id
      [
        "https://networkservices.googleapis.com/v1/projects/#{project_id}/locations/-/agentGateways",
        "https://networkservices.googleapis.com/v1beta1/projects/#{project_id}/locations/-/agentGateways",
        "https://dlp.googleapis.com/v2/projects/#{project_id}/locations/us-central1/inspectTemplates",
        "https://dlp.googleapis.com/v2/projects/#{project_id}/inspectTemplates"
      ].each do |url|
        break if agw_found
        begin
          uri = URI(url)
          req = Net::HTTP::Get.new(uri)
          auth_handle.authorization.apply!(req)
          resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
          if resp.is_a?(Net::HTTPSuccess) && (
            resp.body.include?('agent-gateway') ||
            resp.body.include?('AGENT_TO_ANYWHERE') ||
            resp.body.include?('agw-ssn-inspect-template') ||
            resp.body.include?('KOREA_RRN')
          )
            agw_found = true
          end
        rescue
          nil
        end
      end
    end

    log_found = false
    begin
      if !agw_found && logging && project_id
        lab_start_time = Time.at(Time.now.to_i - 86400)
        log_filters = [
          'timestamp>"' + lab_start_time.utc.iso8601 + '"',
          '(protoPayload.resourceName:"agent-gateway" OR protoPayload.resourceName:"agw-request-template" OR protoPayload.resourceName:"agw-response-template" OR protoPayload.resourceName:"agw-ssn-inspect-template")'
        ]
        req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
        req.resource_names = ['projects/' + project_id]
        req.filter = log_filters.join(" AND ")
        query_logs = logging.list_entry_log_entries(req)&.entries || []
        log_found = true if query_logs.count > 0
      end
    rescue
      nil
    end

    if agw_found || log_found
      ret_hash = {
        :done => true,
        :score => maximum_score,
        :message => 'success',
        :student_message => 'success'
      }
    else
      ret_hash[:message] = 'agw_missing'
      ret_hash[:student_message] = 'agw_missing'
    end
  rescue => e
    ret_hash[:message] = e.message
    ret_hash[:student_message] = 'agw_missing'
  end

  return ret_hash
end
