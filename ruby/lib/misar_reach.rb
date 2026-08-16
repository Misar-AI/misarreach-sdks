require_relative "misar_reach/errors"
require_relative "misar_reach/client"

# Official Ruby SDK for the MisarReach developer API (api.misar.io/reach/api).
#
#   require "misar_reach"
#   reach = MisarReach.new(api_key: "mrk_...")
#   reach.leads.search(query: "SaaS founders", location: "US")
#
module MisarReach
  def self.new(**kwargs)
    Client.new(**kwargs)
  end
end
