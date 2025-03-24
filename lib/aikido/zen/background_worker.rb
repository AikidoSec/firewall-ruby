module Aikido::Zen
  # Generic background worker class backed by queue. Mean to be used by any
  # background process that needs to do heavy tasks.
  class BackgroundWorker
    # @param block [block] A block that receives 1 message directly from the queue
    def initialize(&block)
      @queue = Queue.new
      @block = block
    end

    # starts the background thread, blocking the thread until a new messages arrives
    # or the queue is stopped.
    def start!
      @thread = Thread.new do
        while running? || actions?
          @block.call(wait_for_action)
        end
      end
    end

    def restart
      stop
      start
    end

    def stop
      queue.close # stop accepting messages, hence draining the queue.
      @thread.join
    end

    def enqueue(scan)
      queue.push(scan)
    end

    private

    attr_reader :queue, :threads
    def actions?
      !queue.empty?
    end

    def running?
      !queue.closed?
    end

    def dequeue_action
      queue.pop(true)
    end

    def wait_for_action
      queue.pop(false)
    end
  end
end
