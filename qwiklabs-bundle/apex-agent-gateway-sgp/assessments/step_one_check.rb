def step_one_check(handles:, maximum_score:, resources:)
  ret_hash = { :score => 0, :message => "", :student_message => "" }

  begin
    compute = handles['project_0.ComputeV1']
    logging = handles['project_0.LoggingV2']
    project_id = (logging.project rescue nil) || (compute.project rescue nil) || (resources.dig('project_0', 'project_id') rescue nil) || (resources['project_0.project_id'] rescue nil)

    subnet_found = false
    begin
      subnetworks_list = compute.aggregated_subnetwork_list&.items || {}
      subnetworks_list.each do |_region, scoped_list|
        next unless scoped_list&.subnetworks
        scoped_list.subnetworks.each do |subnet|
          subnet_found = true if subnet.name == 'proxy-only-subnet'
        end
      end
    rescue
      begin
        subnetworks_list = compute.list_aggregated_subnetworks&.items || {}
        subnetworks_list.each do |_region, scoped_list|
          next unless scoped_list&.subnetworks
          scoped_list.subnetworks.each do |subnet|
            subnet_found = true if subnet.name == 'proxy-only-subnet'
          end
        end
      rescue
        nil
      end
    end

    log_found = false
    begin
      lab_start_time = Time.at(Time.now.to_i - 86400)
      log_filters = [
        'timestamp>"' + lab_start_time.utc.iso8601 + '"',
        '(protoPayload.resourceName:"agent-egress" OR protoPayload.resourceName:"agent-gateway-na" OR protoPayload.resourceName:"proxy-only-subnet")'
      ]
      req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
      req.resource_names = ['projects/' + project_id]
      req.filter = log_filters.join(" AND ")
      query_logs = logging.list_entry_log_entries(req)&.entries || []
      log_found = true if query_logs.count > 0
    rescue
      nil
    end

    if subnet_found || log_found
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
