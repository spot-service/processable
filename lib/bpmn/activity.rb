module Bpmn
  class Activity < Step
    attr_accessor :attachments

    def initialize(moddle)
      super
      @attachments = []
    end
  end
end