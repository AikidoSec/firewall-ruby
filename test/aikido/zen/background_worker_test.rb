# frozen_string_literal: true

require "test_helper"

class Aikido::Zen::BackgroundWorkerTest < ActiveSupport::TestCase
  setup do
    @state = []
    @background_worker = Aikido::Zen::BackgroundWorker.new do |work_unit|
      @state << work_unit
    end
  end

  test "background worker receives and dispatch all the messages to be processed" do
    @background_worker.start

    @background_worker.enqueue 1
    @background_worker.enqueue 2
    @background_worker.enqueue 3

    # Let's allow some time for the other thread to process all the messages
    sleep 0.1

    assert_equal [1, 2, 3], @state
  end

  test "stopping the background worker blocks and drain all the messages" do
    @background_worker.start

    @background_worker.enqueue 1
    @background_worker.enqueue 2
    @background_worker.enqueue 3

    @background_worker.stop

    assert_raises(ClosedQueueError) { @background_worker.enqueue 4 }

    assert_equal [1, 2, 3], @state

    assert_raises(ClosedQueueError) { @background_worker.enqueue 5 }
  end

  test "background worker can be restarted, ensuring all messages are processed" do
    @background_worker.start

    @background_worker.enqueue 1
    @background_worker.enqueue 2
    @background_worker.enqueue 3

    @background_worker.restart

    assert_equal [1, 2, 3], @state

    @background_worker.enqueue 4
    @background_worker.enqueue 5
    @background_worker.enqueue 6
    @background_worker.enqueue 7

    # Let's allow some time for the other thread to process all the messages
    sleep 0.1

    assert_equal [1, 2, 3, 4, 5, 6, 7], @state
  end
end
