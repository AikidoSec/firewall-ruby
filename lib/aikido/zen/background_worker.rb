module Aikido::Zen
  # Generic background worker class backed by queue. Meant to be used by any
  # background process that needs to do heavy tasks.
  class BackgroundWorker
    # @param block [block] A block that receives 1 message directly from the queue
    def initialize(&block)
      @queue = Queue.new
      @block = block
    end

    # starts the background thread, blocking the thread until a new messages arrives
    # or the queue is stopped.
    def start
      @thread = Thread.new do
        while running? || actions?
          action = wait_for_action
          @block.call(action) unless action.nil?
        end
      end
    end

    def restart
      stop
      @queue = Queue.new # re-open the queue
      start
    end

    # Drain the queue to do not lose any messages
    def stop
      @queue.close # stop accepting messages
      @thread.join # wait for the queue to be drained
    end

    def enqueue(scan)
      @queue.push(scan)
    end

    private

    def actions?
      !@queue.empty?
    end

    def running?
      !@queue.closed?
    end

    def wait_for_action
      @queue.pop(false)
    end
  end
end
