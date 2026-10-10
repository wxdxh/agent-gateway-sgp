require 'net/http'
require 'json'
require 'uri'

def step_two_check(handles:, maximum_score:, resources:)
  ret_hash = { :done => false, :score => 0, :message => "", :student_message => "" }

  begin
    logging = handles['project_0.LoggingV2']
    project_id = (resources.dig('project_0', 'project_id') rescue nil) ||
                 (resources['project_0.project_id'] rescue nil) ||
                 (logging.project rescue nil)

    mcp_found = false
    begin
      if logging && project_id
        uri = URI("https://run.googleapis.com/v2/projects/#{project_id}/locations/-/services")
        req = Net::HTTP::Get.new(uri)
        logging.authorization.apply!(req)
        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        if resp.is_a?(Net::HTTPSuccess) && resp.body.include?('banking-mcp-server')
          mcp_found = true
        end
      end
    rescue
      nil
    end

    if !mcp_found && logging && project_id
      begin
        lab_start_time = Time.at(Time.now.to_i - 86400)
        log_filters = [
          'timestamp>"' + lab_start_time.utc.iso8601 + '"',
          'protoPayload.resourceName:"banking-mcp-server"'
        ]
        req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
        req.resource_names = ['projects/' + project_id]
        req.filter = log_filters.join(" AND ")
        query_logs = logging.list_entry_log_entries(req)&.entries || []
        mcp_found = true if query_logs.count > 0
      rescue
        nil
      end
    end

    if mcp_found
      ret_hash = {
        :done => true,
        :score => maximum_score,
        :message => 'success',
        :student_message => 'success'
      }
    else
      ret_hash[:message] = 'mcp_missing'
      ret_hash[:student_message] = 'mcp_missing'
    end
  rescue => e
    ret_hash[:message] = e.message
    ret_hash[:student_message] = 'mcp_missing'
  end

  return ret_hash
end
