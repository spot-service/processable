# frozen_string_literal: true

module Bpmn
  class Flow < Element
    attr_accessor :source_ref, :target_ref
    attr_accessor :source, :target

    def initialize(moddle)
      super
      @source_ref = moddle["sourceRef"]
      @target_ref = moddle["targetRef"]
      @source = nil
      @target = nil
    end
  end

  class SequenceFlow < Flow
    attr_accessor :condition

    def initialize(moddle)
      super
      @condition = Expression.new(moddle["conditionExpression"]) if moddle["conditionExpression"]
    end

    def evaluate(step_execution)
      return true unless condition&.body
      step_execution.evaluate_condition(condition)
    end
  end
end
