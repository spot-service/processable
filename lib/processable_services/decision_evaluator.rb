# frozen_string_literal: true

module ProcessableServices
  class DecisionEvaluator < ApplicationService
    EVALUATE_BIN = File.expand_path(File.dirname(__FILE__)) + "/decision_evaluator.js"

    def initialize(decision_id, source, context, functions: [])
      super()
      @decision_id = decision_id
      @source = source
      @context = context
      @functions = functions
    end

    def call
      command = [EVALUATE_BIN, @decision_id, @source, @context.to_json, *@functions].shelljoin
      result = `#{command}`
      if $? == 0
        JSON.parse(result)
      else
        raise result
      end
    end
  end
end
