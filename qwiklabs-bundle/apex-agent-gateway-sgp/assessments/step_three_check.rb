def step_three_check(handles:, maximum_score:, resources:)
  ret_hash = { :score => 0, :message => "", :student_message => "" }

  begin
    compute = handles['project_0.ComputeV1']
    project_id = resources['project_0']['project_id']

    psc_ip_found = false
    addresses_list = compute.list_aggregated_addresses(project_id)&.items || {}
    addresses_list.each do |_region, scoped_list|
      next unless scoped_list&.addresses
      scoped_list.addresses.each do |addr|
        if addr.name == 'sgp-psc-ip'
          psc_ip_found = true
          break
        end
      end
    end

    psc_rule_found = false
    rules_list = compute.list_aggregated_forwarding_rules(project_id)&.items || {}
    rules_list.each do |_region, scoped_list|
      next unless scoped_list&.forwarding_rules
      scoped_list.forwarding_rules.each do |rule|
        if rule.name == 'sgp-psc-endpoint'
          psc_rule_found = true
          break
        end
      end
    end

    if psc_ip_found && psc_rule_found
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
