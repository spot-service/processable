require "test_helper"

module Processable
  describe Execution do
    let(:bpmn_source) { fixture_source('hello_world.bpmn') }
    let(:dmn_source) { fixture_source('choose_greeting.dmn') }
    let(:services) {
      {
        tell_fortune: proc { |variables|
          raise "Fortune not found? Abort, Retry, Ignore." if variables[:error]
          [
            "The fortune you seek is in another cookie.",
            "A closed mouth gathers no feet.",
            "A conclusion is simply the place where you got tired of thinking.",
            "A cynic is only a frustrated optimist.",
            "A foolish man listens to his heart. A wise man listens to cookies.",
            "You will die alone and poorly dressed.",
            "A fanatic is one who can't change his mind, and won't change the subject.",
            "If you look back, you’ll soon be going that way.",
            "You will live long enough to open many fortune cookies.",
            "An alien of some sort will be appearing to you shortly.",
            "Do not mistake temptation for opportunity.",
            "Flattery will go far tonight.",
            "He who laughs at himself never runs out of things to laugh at.",
            "He who laughs last is laughing at you.",
            "He who throws dirt is losing ground.",
            "Some men dream of fortunes, others dream of cookies.",
            "The greatest danger could be your stupidity.",
            "We don’t know the future, but here’s a cookie.",
            "The world may be your oyster, but it doesn't mean you'll get its pearl.",
            "You will be hungry again in one hour.",
            "The road to riches is paved with homework.",
            "You can always find happiness at work on Friday.",
            "Actions speak louder than fortune cookies.",
            "Because of your melodic nature, the moonlight never misses an appointment.",
            "Don’t behave with cold manners.",
            "Don’t forget you are always on our minds.",
            "Help! I am being held prisoner in a fortune cookie factory.",
            "It’s about time I got out of that cookie.",
            "Never forget a friend. Especially if he owes you.",
            "Never wear your best pants when you go to fight for freedom.",
            "Only listen to the fortune cookie; disregard all other fortune telling units.",
            "It is a good day to have a good day.",
            "All fortunes are wrong except this one.",
            "Someone will invite you to a Karaoke party.",
            "That wasn’t chicken.",
            "There is no mistake so great as that of being always right.",
            "You love Chinese food.",
            "I am worth a fortune.",
            "No snowflake feels responsible in an avalanche.",
            "You will receive a fortune cookie.",
            "Some fortune cookies contain no fortune.",
            "Don’t let statistics do a number on you.",
            "You are not illiterate.",
            "May you someday be carbon neutral.",
            "You have rice in your teeth.",
            "Avoid taking unnecessary gambles. Lucky numbers: 12, 15, 23, 28, 37",
            "Ask your mom instead of a cookie.",
            "This cookie contains 117 calories.",
            "Hard work pays off in the future. Laziness pays off now.",
            "You think it’s a secret, but they know.",
            "If a turtle doesn’t have a shell, is it naked or homeless?",
            "Change is inevitable, except for vending machines.",
            "Don’t eat the paper.",
          ].sample
        },
      }
    }
    let(:log) { @log }
    let(:listeners) { 
      {
        process_started: proc { |event| log.push event },
        step_waiting: proc { |event| log.push event },
        step_ended: proc { |event| log.push event },
        process_ended: proc { |event| log.push event },
      }
    }
    let(:last)
    let(:context) { Context.new(sources: [bpmn_source, dmn_source], services: services, listeners: listeners) }
    let(:process) { context.process_by_id('HelloWorld') }

    describe :definition do
      let(:user_task) { process.element_by_id('IntroduceYourself') }

      it 'should parse the process' do
        _(user_task).wont_be_nil
      end
    end

    describe :execution do
      let(:execution) { @execution }
      let(:user_step) { execution.step_by_id('IntroduceYourself') }

      before do 
        @log = []
        @execution = Execution.start(context: context, process_id: 'HelloWorld', variables: { greet: true, cookie: true })
      end

      it 'should start the process' do
        _(execution.started?).must_equal true
        _(user_step.waiting?).must_equal true
        _(log.last[:event]).must_equal :step_waiting
      end

      describe :invoke do
        before { user_step.invoke(variables: { name: "Eric", language: "it", formal: false }) }

        it 'should end the process' do
          _(execution.ended?).must_equal true
          _(user_step.ended?).must_equal true
        end
      end

      describe :serialization do
        let(:json) { @json }
        let(:new_execution) { @new_execution }

        before do 
          @json = execution.to_json(include: :steps)
          @new_execution = Execution.deserialize(json, context: context)
        end

        it 'should be lossless' do
          _(new_execution.serialize).must_equal(json)
        end

        describe :execution_after_serialization do
          let (:user_step) { new_execution.step_by_id('IntroduceYourself') }

          before { user_step.invoke(variables: { name: "Eric", language: "it", formal: false }) }

          it 'should end the process' do
            _(new_execution.ended?).must_equal true
            _(user_step.ended?).must_equal true
          end
        end
      end
    end
  end
end