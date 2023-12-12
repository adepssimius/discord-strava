module DiscordStrava
  module Commands
    class Set < Discord::Commands::Command
      include DiscordStrava::Commands::Mixins::Subscribe
      include DiscordStrava::Loggable

      subscribe_command 'strada' => 'set' do |command|
        logger.info "SET: #{command}, #{command.user}"
        options = command[:data][:options]
        first_option = options.first if options
        first_selection = first_option[:options] if first_option
        if first_selection.empty? || options.first[:name] != 'set'
          messages = [
            "Activities for team #{command.team.guild_name} display *#{command.team.units_s}*.",
            "Activity fields are *#{command.team.activity_fields_s}*.",
            "Maps for team #{command.team.guild_name} are *#{command.team.maps_s}*.",
            "Posts will #{command.team.anonymize? ? '' : 'not '}be anonymized.",
            "Your activities will #{command.user.sync_activities? ? '' : 'not '}sync.",
            "Your private activities will #{command.user.private_activities? ? '' : 'not '}be posted.",
            "Your followers only activities will #{command.user.followers_only_activities? ? '' : 'not '}be posted."
          ]
          logger.info "SET: #{command.team}, user=#{command.user} - set"
          messages.join("\n")
        else
          option = first_selection.first
          k = option[:name]
          v = option[:value]
          case k
          when 'sync'
            changed = v && command.user.sync_activities != v
            command.user.update_attributes!(sync_activities: v) unless v.nil?
            logger.info "SET: #{command.team}, user=#{command.user} - sync set to #{command.user.sync_activities}"
            "Your activities will#{changed ? (command.user.sync_activities? ? ' now' : ' no longer') : (command.user.sync_activities? ? '' : ' not')} sync."
          when 'private'
            changed = v && command.user.private_activities != v
            command.user.update_attributes!(private_activities: v) unless v.nil?
            logger.info "SET: #{command.team}, user=#{command.user} - private set to #{command.user.private_activities}"
            "Your private activities will#{changed ? (command.user.private_activities? ? ' now' : ' no longer') : (command.user.private_activities? ? '' : ' not')} be posted."
          when 'followers'
            changed = v && command.user.followers_only_activities != v
            command.user.update_attributes!(followers_only_activities: v) unless v.nil?
            logger.info "SET: #{command.team}, user=#{command.user} - followers_only set to #{command.user.followers_only_activities}"
            "Your followers only activities will#{changed ? (command.user.followers_only_activities? ? ' now' : ' no longer') : (command.user.followers_only_activities? ? '' : ' not')} be posted."
          when 'units'
            case v
            when 'metric'
              v = 'km'
            when 'imperial'
              v = 'mi'
            end
            changed = v && command.team.units != v
            if !command.user.guild_owner? && changed
              logger.info "SET: #{command.team} - not admin, units remain set to #{command.team.units}"
              "Sorry, only a Discord admin can change units. Activities for team #{command.team.guild_name} display *#{command.team.units_s}*."
            else
              command.team.update_attributes!(units: v) unless v.nil?
              logger.info "SET: #{command.team} - units set to #{command.team.units}"
              "Activities for team #{command.team.guild_name}#{changed ? ' now' : ''} display *#{command.team.units_s}*."
            end
          when 'fields'
            parsed_fields = ActivityFields.parse_s(v) if v
            changed = parsed_fields && command.team.activity_fields != parsed_fields
            if !command.user.guild_owner? && changed
              logger.info "SET: #{command.team} - not admin, activity fields remain set to #{command.team.activity_fields.and}"
              "Sorry, only a Discord admin can change fields. Activity fields for team #{command.team.guild_name} are *#{command.team.activity_fields_s}*."
            else
              command.team.update_attributes!(activity_fields: parsed_fields) if changed && parsed_fields&.any?
              logger.info "SET: #{command.team} - activity fields set to #{command.team.activity_fields.and}"
              "Activity fields for team #{command.team.guild_name} are#{changed ? ' now' : ''} *#{command.team.activity_fields_s}*."
            end
          when 'maps'
            parsed_value = MapTypes.parse_s(v) if v
            changed = parsed_value && command.team.maps != parsed_value
            if !command.user.guild_owner? && changed
              logger.info "SET: #{command.team} - not admin, maps remain set to #{command.team.maps}"
              "Sorry, only a Discord admin can change maps. Maps for team #{command.team.guild_name} are *#{command.team.maps_s}*."
            else
              command.team.update_attributes!(maps: parsed_value) if parsed_value
              logger.info "SET: #{command.team} - maps set to #{command.team.maps}"
              "Maps for team #{command.team.guild_name} are#{changed ? ' now' : ''} *#{command.team.maps_s}*."
            end
          when 'anonymize'
            changed = v && command.team.anonymize != v
            command.team.update_attributes!(anonymize: v) unless v.nil?
            logger.info "SET: #{command.team} - anonymize set to #{command.team.anonymize}"
            "Names in posts for team #{command.team.guild_name} will #{changed ? (command.team.anonymize? ? ' now' : ' no longer') : } be obscured in activity posts."
          else
            "Invalid setting #{k}, type `help` for instructions."
          end
        end
      end
    end
  end
end
