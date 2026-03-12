# frozen_string_literal: true

module ::DiscourseZoteroBridge
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseZoteroBridge
    config.autoload_paths << File.join(config.root, "lib")
  end
end
