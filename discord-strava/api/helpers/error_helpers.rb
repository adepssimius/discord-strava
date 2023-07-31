module Api
  module Helpers
    module ErrorHelpers
      extend ActiveSupport::Concern

      included do
        rescue_from :all, backtrace: true do |e|
          backtrace = e.backtrace.join("\n  ")
          Api::Middleware.logger.error "#{e.class.name}: #{e.message}\n  #{backtrace}"
          error = { type: 'other_error', message: e.message }
          error[:backtrace] = backtrace
          rack_response(error.to_json, 400)
        end
        rescue_from Faraday::Error do |e|
          backtrace = e.backtrace.join("\n  ")
          Api::Middleware.logger.error "#{e.class.name}: #{e.message} (#{e.response[:body]})\n  #{backtrace}"
          error = { type: 'other_error', message: "#{e.message} (#{e.response[:body]['error']})" }
          error[:backtrace] = backtrace
          rack_response(error.to_json, 400)
        end
        # rescue document validation errors into detail json
        rescue_from Mongoid::Errors::Validations do |e|
          backtrace = e.backtrace.join("\n  ")
          Api::Middleware.logger.warn "#{e.class.name}: #{e.message}\n  #{backtrace}"
          rack_response({
            type: 'param_error',
            message: e.document.errors.full_messages.uniq.join(', ') + '.',
            detail: e.document.errors.messages.transform_values(&:uniq)
          }.to_json, 400)
        end
        rescue_from Grape::Exceptions::Validation do |e|
          backtrace = e.backtrace.join("\n  ")
          Api::Middleware.logger.warn "#{e.class.name}: #{e.message}\n  #{backtrace}"
          rack_response({
            type: 'param_error',
            message: 'Invalid parameters.',
            detail: { e.params.join(', ') => [e.message] }
          }.to_json, 400)
        end
        rescue_from Grape::Exceptions::ValidationErrors do |e|
          backtrace = e.backtrace.join("\n  ")
          Api::Middleware.logger.warn "#{e.class.name}: #{e.message}\n  #{backtrace}"
          rack_response({
            type: 'param_error',
            message: 'Invalid parameters.',
            detail: e.errors.transform_keys do |k|
              # JSON does not permit having a key of type Array
              k.count == 1 ? k.first : k.join(', ')
            end
          }.to_json, 400)
        end
      end
    end
  end
end
