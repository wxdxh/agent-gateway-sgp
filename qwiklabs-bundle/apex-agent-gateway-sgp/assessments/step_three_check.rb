require 'net/http'
require 'json'
require 'uri'

def step_three_check(handles:, maximum_score:, resources:)
  ret_hash = { :done => false, :score => 0, :message => "", :student_message => "" }

  begin
    compute = handles['project_0.ComputeV1']
    logging = handles['project_0.LoggingV2']
    auth_handle = compute || logging
    project_id = (resources.dig('project_0', 'project_id') rescue nil) ||
                 (resources['project_0.project_id'] rescue nil) ||
                 (compute.project rescue nil) ||
                 (logging.project rescue nil)

    psc_found = false
    begin
      rules_list = compute.list_aggregated_forwarding_rules(project_id, freeze_args: true)&.items || {}
      rules_list.each do |_region, scoped_list|
        next unless scoped_list&.forwarding_rules
        scoped_list.forwarding_rules.each do |rule|
          psc_found = true if rule.name == 'sgp-psc-endpoint'
        end
      end
    rescue
      begin
        rules_list = compute.list_aggregated_forwarding_rules&.items || {}
        rules_list.each do |_region, scoped_list|
          next unless scoped_list&.forwarding_rules
          scoped_list.forwarding_rules.each do |rule|
            psc_found = true if rule.name == 'sgp-psc-endpoint'
          end
        end
      rescue
        nil
      end
    end

    if !psc_found && auth_handle && project_id
      begin
        uri = URI("https://compute.googleapis.com/compute/v1/projects/#{project_id}/aggregated/forwardingRules")
        req = Net::HTTP::Get.new(uri)
        auth_handle.authorization.apply!(req)
        resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        if resp.is_a?(Net::HTTPSuccess) && resp.body.include?('sgp-psc-endpoint')
          psc_found = true
        end
      rescue
        nil
      end
    end

    if !psc_found && logging && project_id
      begin
        lab_start_time = Time.at(Time.now.to_i - 86400)
        log_filters = [
          'timestamp>"' + lab_start_time.utc.iso8601 + '"',
          '(protoPayload.resourceName:"sgp-psc-endpoint" OR protoPayload.resourceName:"sgp-psc-ip")'
        ]
        req = Google::Apis::LoggingV2::ListLogEntriesRequest.new
        req.resource_names = ['projects/' + project_id]
        req.filter = log_filters.join(" AND ")
        query_logs = logging.list_entry_log_entries(req)&.entries || []
        psc_found = true if query_logs.count > 0
      rescue
        nil
      end
    end

    if psc_found
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
