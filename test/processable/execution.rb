# frozen_string_literal: true

module Processable
  class Execution
    include ActiveModel::Model
    include ActiveModel::Serializers::JSON

    attr_accessor :id, :status, :started_at, :ended_at, :variables, :tokens_in, :tokens_out, :start_event_id, :timer_expires_at, :message_names, :error_names, :condition
    attr_accessor :step, :parent, :children, :context, :attached_to_id

    def self.start(context:, process_id:, variables: {}, start_event_id: nil, parent: nil)
      process = context.process_by_id(process_id)
      raise ExecutionError.new("Process with id #{process_id} not found.") unless process
      Execution.new(context: context, step: process, variables: variables, start_event_id: start_event_id, parent: parent).tap do |execution|
        context.executions.push execution
        execution.start
      end
    end

    def self.start_with_message(context:, message_name:, variables: {})
      [].tap do |executions|
        context.processes.map do |process|
          process.start_events.map do |start_event|
            start_event.message_event_definitions.map do |message_event_definition|
              if message_name == message_event_definition.message_name
                Execution.start(context: context, process_id: process&.id, variables: variables, start_event_id: start_event.id).tap { |execution| executions.push execution }
              end
            end
          end
        end
      end
    end

    def initialize(attributes={})
      super(attributes).tap do
        @id ||= SecureRandom.uuid
        @status ||= "activated"
        @variables ||= {}.with_indifferent_access
        @tokens_in ||= []
        @tokens_out ||= []
        @message_names ||= []
        @error_names ||= []
        @children ||= []
      end
    end

    def attached_to
      @attached_to ||= parent.children.find { |child| child.id == attached_to_id } if parent
    end

    def started?
      started_at.present?
    end

    def ended?
      ended_at.present?
    end

    def running?
      status == "running"
    end

    def waiting?
      status == "waiting"
    end

    def completed?
      status == "completed"
    end

    def terminated?
      status == "terminated"
    end

    def bind_variable_scope(scope)
      parent.bind_variable_scope(scope) if parent
      variables.keys.each { |key| scope[key] = variables[key] }
    end

    def execute_steps(steps)
      steps.each { |step| execute_step(step) }
    end

    def execute_step(step, attached_to: nil, sequence_flow: nil)
      child_execution = children.find { |child| child.step.id == step.id }
      child_execution = Execution.new(context: context, step: step, parent: self, attached_to_id: attached_to&.id).tap { |ce| children.push ce } unless child_execution
      child_execution.tokens_in += [sequence_flow.id] if sequence_flow
      child_execution.start
    end

    def invoke_listeners(type, sequence_flow = nil)
      context.listeners.each { |listener| listener[type].call(self, sequence_flow) if listener[type] }
    end

    def start
      @status = "running"
      @started_at = Time.zone.now
      context.notify_listener({ event: :started, execution: self })
      step.attachments.each { |attachment| parent.execute_step(attachment, attached_to: self) } if step.is_a?(Bpmn::Activity)
      continue
    end

    def wait
      @status = "waiting"
      context.notify_listener({ event: :waited, execution: self })
    end

    def continue
      step.execute(self)
    end

    def terminate
      @status = "terminated"
      self.end
    end

    def end(notify_parent = false)
      @status = "completed" unless status == "terminated"
      parent.variables.merge!(variables) if parent && variables.present?
      @ended_at = Time.zone.now
      context.notify_listener({ event: :ended, execution: self })
      children.each { |child| child.terminate unless child.ended? }
      parent.children.each { |child| child.terminate if child.attached_to == self && child.waiting? } if parent
      parent.has_ended(self) if parent && notify_parent
    end

    def take_all(sequence_flows)
      sequence_flows.each { |sequence_flow| take(sequence_flow) }
    end

    def take(sequence_flow)
      to_step = sequence_flow.target
      .step_by_element_id.push sequence_flow.id
      .step_by_element_id.uniq!
      context.notify_listener({ event: :taken, execution: self, sequence_flow: sequence_flow })
      parent.execute_step(to_step, sequence_flow: sequence_flow)
    end

    def signal(result = nil)
      @variables.merge!(result_to_variables(result)) if result.present?
      #raise ExecutionError.new("Cannot signal a step execution that has ended.") if ended?
      step.signal(self)
    end

    def throw_message(message_name, variables: {})
      waiting_children.each do |child|
        step = child.step
        if step.is_a?(Bpmn::Event) && step.message_event_definitions.any? { |message_event_definition| message_event_definition.message_name == message_name }
          child.signal(variables)
          break
        end
      end
      context.notify_listener({ event: :thrown, execution: self, message_name: message_name })
    end

    def throw_error(error_name, variables: {})
      waiting_children.each do |child|
        step = child.step
        if step.is_a?(Bpmn::Event) && step.error_event_definitions.any? { |error_event_definition| error_event_definition.error_name == error_name }
          child.signal(variables)
          break
        end
      end
      context.notify_listener({ event: :thrown, execution: self, error_name: error_name })
    end

    def check_expired_timers
      waiting_children.each { |child| child.signal if child.timer_expires_at.present? && Time.zone.now > child.timer_expires_at }
    end

    def evaluate_condition(condition)
      evaluate_expression(condition.body) == true
    end

    def evaluate_expression(expression)
      ProcessableServices::ExpressionEvaluator.call(expression: expression, variables: parent.variables)
    end

    def result_to_variables(result)
      if step.respond_to?(:result_variable) && step.result_variable
        return { "#{step.result_variable}": result }
      else
        if result.is_a? Hash
          result
        else
          {}.tap { |h| h[step.id.underscore] = result }
        end
      end
    end

    def run
      case step.type
      when "bpmn:ServiceTask"
        context.service_task_runner.call(self, context) if context.service_task_runner.present?
      when "bpmn:ScriptTask"
        context.script_task_runner.call(self, context) if context.script_task_runner.present?
      when "bpmn:BusinessRuleTask"
        context.business_rule_task_runner.call(self, context) if context.business_rule_task_runner.present?
      end
    end

    def call(process_id)
      execute_step(context.process_by_id(process_id))
    end

    #
    # Called by the child step executors when they have ended
    #
    def has_ended(_child)
      step.leave(self) if step.is_a?(Bpmn::SubProcess) || step.is_a?(Bpmn::CallActivity)
      self.end(true)
    end

    def child_by_step_id(id)
      children.find { |child| child.step.id == id }
    end

    def waiting_children
      children.filter { |child| child.waiting? }
    end

    def tokens(active_tokens = [])
      children.each do |child|
        active_tokens = active_tokens + child..step_by_element_id
        active_tokens = active_tokens - child.tokens_in if child.ended?
        active_tokens = active_tokens + child.tokens(active_tokens)
      end
      active_tokens.uniq
    end

    def as_json(_options = {})
      {
        id: id,
        step_id: step&.id,
        step_type: step&.type,
        attached_to_id: attached_to_id,
        status: status,
        started_at: started_at,
        ended_at: ended_at,
        variables: variables,
        tokens_in: tokens_in,
        .step_by_element_id: .step_by_element_id,
        message_names: message_names,
        error_names: error_names,
        timer_expires_at: timer_expires_at,
        condition: condition,
        children: children.map { |child| child.as_json },
      }.compact_blank
    end

    def serialize
      to_json
    end

    def self.deserialize(json, context:)
      attributes = JSON.parse(json)
      Execution.from_json(attributes, context: context)
    end

    def self.from_json(attributes, context:)
      step_id = attributes.delete("step_id")
      step_type = attributes.delete("step_type")
      step = step_type == "bpmn:Process" ? context.process_by_id(step_id) : context.element_by_id(step_id)
      child_attributes = attributes.delete("children")
      Execution.new(attributes.merge(step: step)).tap do |execution|
        execution.children = child_attributes.map { |ca| Execution.from_json(ca, context: context) } if child_attributes
      end
    end

    def pretty_json
      JSON.pretty_generate(as_json)
    end
  end

  class Printer
    attr_accessor :execution

    def initialize(execution)
      @execution = execution
    end

    def print
      puts
      puts "#{execution.step.id} #{execution.status} * #{execution.tokens.join(', ')}"
      print_variables unless execution.variables.empty?
      print_children
      puts
    end

    def print_children
      puts
      execution.children.each_with_index do |child, index|
        str = "#{index} #{child.step.type.split(':').last} #{child.step.id}: #{child.status} #{JSON.pretty_generate(variables, {indent: '', object_nl: ' ' }) unless child.variables.empty? }".strip
        str = "#{str} * in: #{child.tokens_in.join(', ')}" if child.tokens_in.present?
        str = "#{str} * out: #{child.tokens_out.join(', ')}" if child.tokens_out.present?
        puts str
      end
    end

    def print_variables
      puts
      puts JSON.pretty_generate(execution.variables)
    end
  end
end