Gem::Specification.new do |spec|
  spec.name          = "misarreach"
  spec.version       = "5.0.2"
  spec.authors       = ["Misar AI"]
  spec.email         = ["hello@misar.io"]
  spec.summary       = "Ruby client for MisarReach: async lead finder with SSE streaming, CRM pipeline, multi-channel campaigns, AI sales agent, autopilot"
  spec.description   = "Ruby client for the MisarReach outreach and lead-generation API (api.misar.io/reach/api). " \
                       "17 resource groups and 94 methods — one for every operation in the published OpenAPI spec: " \
                       "an asynchronous lead finder across 23 sources with Server-Sent Events job streaming, CRM " \
                       "contacts, deals and a Kanban pipeline, multi-step campaigns over email, SMS, WhatsApp, web " \
                       "push and social DMs, an AI sales agent, autopilot, deliverability, and plan and usage " \
                       "reporting. Pure Net::HTTP with no runtime dependencies, typed errors, and retries with " \
                       "exponential back-off. Installs as `misarreach`; requires as `misar_reach`."
  spec.homepage      = "https://www.misarreach.com"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "documentation_uri"     => "https://docs.misar.io/reach",
    "source_code_uri"       => "https://github.com/Misar-AI/misarreach-sdks/tree/main/ruby",
    "changelog_uri"         => "https://github.com/Misar-AI/misarreach-sdks/blob/main/ruby/CHANGELOG.md",
    "bug_tracker_uri"       => "https://github.com/Misar-AI/misarreach-sdks/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.23"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
