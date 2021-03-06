require 'rspec/core/bisect/example_minimizer'
require 'rspec/core/formatters/bisect_formatter'
require 'rspec/core/bisect/server'
require 'support/fake_bisect_runner'

module RSpec::Core
  RSpec.describe Bisect::ExampleMinimizer do
    let(:fake_runner) do
      FakeBisectRunner.new(
        %w[ ex_1 ex_2 ex_3 ex_4 ex_5 ex_6 ex_7 ex_8 ],
        %w[ ex_2 ],
        { "ex_5" => %w[ ex_4 ] }
      )
    end

    it 'repeatedly runs various subsets of the suite, removing examples that have no effect on the failing examples' do
      minimizer = Bisect::ExampleMinimizer.new(fake_runner, RSpec::Core::NullReporter)
      minimizer.find_minimal_repro
      expect(minimizer.repro_command_for_currently_needed_ids).to eq("rspec ex_2 ex_4 ex_5")
    end

    it 'reduces a failure where none of the passing examples are implicated' do
      no_dependents_runner = FakeBisectRunner.new(
        %w[ ex_1 ex_2 ],
        %w[ ex_2 ],
        {}
      )
      minimizer = Bisect::ExampleMinimizer.new(no_dependents_runner, RSpec::Core::NullReporter)
      minimizer.find_minimal_repro
      expect(minimizer.repro_command_for_currently_needed_ids).to eq("rspec ex_2")
    end

    it 'reduces a failure when more than 50% of examples are implicated' do
      fake_runner.always_failures = []
      fake_runner.dependent_failures = { "ex_8" => %w[ ex_1 ex_2 ex_3 ex_4 ex_5 ex_6 ] }
      minimizer = Bisect::ExampleMinimizer.new(fake_runner, RSpec::Core::NullReporter)
      minimizer.find_minimal_repro
      expect(minimizer.repro_command_for_currently_needed_ids).to eq(
        "rspec ex_1 ex_2 ex_3 ex_4 ex_5 ex_6 ex_8"
      )
    end

    it 'reduces a failure with multiple dependencies' do
      fake_runner.always_failures = []
      fake_runner.dependent_failures = { "ex_8" => %w[ ex_1 ex_3 ex_5 ex_7 ] }
      minimizer = Bisect::ExampleMinimizer.new(fake_runner, RSpec::Core::NullReporter)
      minimizer.find_minimal_repro
      expect(minimizer.repro_command_for_currently_needed_ids).to eq(
        "rspec ex_1 ex_3 ex_5 ex_7 ex_8"
      )
    end

    context 'with an unminimisable failure' do
      class RunCountingReporter < RSpec::Core::NullReporter
        attr_accessor :round_count
        attr_accessor :example_count
        def initialize
          @round_count = 0
        end

        def publish(event, *args)
          send(event, *args) if respond_to? event
        end

        def bisect_individual_run_start(_notification)
          self.round_count += 1
        end
      end

      let(:counting_reporter) { RunCountingReporter.new }
      let(:fake_runner) do
        FakeBisectRunner.new(
          %w[ ex_1 ex_2 ex_3 ex_4 ex_5 ex_6 ex_7 ex_8 ex_9 ],
          [],
          "ex_9" => %w[ ex_1 ex_2 ex_3 ex_4 ex_5 ex_6 ex_7 ex_8 ]
        )
      end
      let(:counting_minimizer) do
        Bisect::ExampleMinimizer.new(fake_runner, counting_reporter)
      end

      it 'returns the full command if the failure can not be reduced' do
        counting_minimizer.find_minimal_repro

        expect(counting_minimizer.repro_command_for_currently_needed_ids).to eq(
          "rspec ex_1 ex_2 ex_3 ex_4 ex_5 ex_6 ex_7 ex_8 ex_9"
        )
      end

      it 'detects an unminimisable failure in the minimum number of runs' do
        counting_minimizer.find_minimal_repro

        # The recursive bisection strategy should take 1 + 2 + 4 + 8 = 15 runs
        # to determine that a failure is fully dependent on 8 preceding
        # examples:
        #
        # 1 run to determine that any of the candidates are culprits
        # 2 runs to determine that each half contains a culprit
        # 4 runs to determine that each quarter contains a culprit
        # 8 runs to determine that each candidate is a culprit
        expect(counting_reporter.round_count).to eq(15)
      end
    end

    it 'ignores flapping examples that did not fail on the initial full run but fail on later runs' do
      def fake_runner.run(ids)
        super.tap do |results|
          @run_count ||= 0
          if (@run_count += 1) > 1
            results.failed_example_ids << "ex_8"
          end
        end
      end

      minimizer = Bisect::ExampleMinimizer.new(fake_runner, RSpec::Core::NullReporter)
      minimizer.find_minimal_repro
      expect(minimizer.repro_command_for_currently_needed_ids).to eq("rspec ex_2 ex_4 ex_5")
    end

    it 'aborts early when no examples fail' do
      minimizer = Bisect::ExampleMinimizer.new(FakeBisectRunner.new(
        %w[ ex_1 ex_2 ], [],  {}
      ), RSpec::Core::NullReporter)

      expect {
        minimizer.find_minimal_repro
      }.to raise_error(RSpec::Core::Bisect::BisectFailedError, /No failures found/i)
    end

    context "when the `repro_command_for_currently_needed_ids` is queried before it has sufficient information" do
      it 'returns an explanation that will be printed when the bisect run is aborted immediately' do
        minimizer = Bisect::ExampleMinimizer.new(FakeBisectRunner.new([], [], {}), RSpec::Core::NullReporter)
        expect(minimizer.repro_command_for_currently_needed_ids).to include("Not yet enough information")
      end
    end
  end
end
