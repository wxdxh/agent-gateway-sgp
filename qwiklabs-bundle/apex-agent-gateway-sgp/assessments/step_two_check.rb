def step_two_check(handles:, maximum_score:, resources:)
  ret_hash = { :score => 0, :message => "", :student_message => "" }

  begin
    logging = handles['project_0.LoggingV2']
    project_id = resources['project_0']['project_id'] || logging.project

    lab_start_time = Time.at(Time.now.to_i - 54000)
    log_filters = [
      'timestamp>"' + lab_start_time.utc.iso8601 + '"',
      'protoPayload.serviceName="run.googleapis.com"',
      'protoPayload.resourceName:"services/banking-mcp-server"'
    ]
    req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
    req.resource_names = ['projects/' + project_id]
    req.filter = log_filters.join(" AND ")
    query_logs = logging.list_entry_log_entries(req)&.entries || []

    if query_logs.count > 0
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
