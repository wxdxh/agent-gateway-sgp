def step_one_check(handles:, maximum_score:, resources:)
  ret_hash = { :score => 0, :message => "", :student_message => "" }

  begin
    compute = handles['project_0.ComputeV1']
    logging = handles['project_0.LoggingV2']
    project_id = resources['project_0']['project_id'] || logging.project

    subnet_found = false
    subnetworks_list = compute.list_aggregated_subnetworks(project_id)&.items || {}
    subnetworks_list.each do |_region, scoped_list|
      next unless scoped_list&.subnetworks
      scoped_list.subnetworks.each do |subnet|
        if subnet.name == 'proxy-only-subnet'
          subnet_found = true
          break
        end
      end
    end

    lab_start_time = Time.at(Time.now.to_i - 54000)
    log_filters = [
      'timestamp>"' + lab_start_time.utc.iso8601 + '"',
      'protoPayload.serviceName="networkservices.googleapis.com"',
      'protoPayload.resourceName:"agentGateways/agent-egress"'
    ]
    req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
    req.resource_names = ['projects/' + project_id]
    req.filter = log_filters.join(" AND ")
    query_logs = logging.list_entry_log_entries(req)&.entries || []

    if subnet_found && query_logs.count > 0
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
