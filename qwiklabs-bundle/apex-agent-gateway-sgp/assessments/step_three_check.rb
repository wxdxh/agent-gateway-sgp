def step_three_check(handles:, maximum_score:, resources:)
  ret_hash = { :score => 0, :message => "", :student_message => "" }

  begin
    compute = handles['project_0.ComputeV1']
    logging = handles['project_0.LoggingV2']
    project_id = (compute.project rescue nil) || (logging.project rescue nil) || (resources.dig('project_0', 'project_id') rescue nil) || (resources['project_0.project_id'] rescue nil)

    psc_ip_found = false
    begin
      addresses_list = compute.list_aggregated_addresses&.items || {}
      addresses_list.each do |_region, scoped_list|
        next unless scoped_list&.addresses
        scoped_list.addresses.each do |addr|
          psc_ip_found = true if addr.name == 'sgp-psc-ip'
        end
      end
    rescue
      begin
        addresses_list = compute.aggregated_address_list&.items || {}
        addresses_list.each do |_region, scoped_list|
          next unless scoped_list&.addresses
          scoped_list.addresses.each do |addr|
            psc_ip_found = true if addr.name == 'sgp-psc-ip'
          end
        end
      rescue
        nil
      end
    end

    psc_rule_found = false
    begin
      rules_list = compute.list_aggregated_forwarding_rules&.items || {}
      rules_list.each do |_region, scoped_list|
        next unless scoped_list&.forwarding_rules
        scoped_list.forwarding_rules.each do |rule|
          psc_rule_found = true if rule.name == 'sgp-psc-endpoint'
        end
      end
    rescue
      begin
        rules_list = compute.aggregated_forwarding_rule_list&.items || {}
        rules_list.each do |_region, scoped_list|
          next unless scoped_list&.forwarding_rules
          scoped_list.forwarding_rules.each do |rule|
            psc_rule_found = true if rule.name == 'sgp-psc-endpoint'
          end
        end
      rescue
        nil
      end
    end

    log_found = false
    begin
      if logging && project_id
        lab_start_time = Time.at(Time.now.to_i - 86400)
        log_filters = [
          'timestamp>"' + lab_start_time.utc.iso8601 + '"',
          '(protoPayload.resourceName:"sgp-psc-endpoint" OR protoPayload.resourceName:"sgp-psc-ip")'
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

    if (psc_ip_found && psc_rule_found) || psc_rule_found || log_found
      ret_hash = {
        :done => true,
        :score => maximum_score,
        :message => 'success',
        :student_message => 'success'
      }
    else
      ret_hash[:message] = 'psc_missing'
      ret_hash[:student_message] = 'psc_missing'
    end
  rescue => e
    ret_hash[:message] = e.message
    ret_hash[:student_message] = 'psc_missing'
  end

  return ret_hash
end
