require_relative "timeout"

class FiberScheduler
  class Timeouts
    def initialize
      # Array is sorted by Timeout#time
      @timeouts = []
    end

    def call
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      while @timeouts.any? && @timeouts.first.time <= now
        timeout = @timeouts.shift
        unless timeout.disabled?
          timeout.call
        end
      end
    end

    def raise_in(duration, *args, **options, &block)
      call_in(duration, :raise, *args, **options, &block)
    end

    def transfer_in(duration, *args, **options, &block)
      call_in(duration, :transfer, *args, **options, &block)
    end

    def interval
      # Prune disabled timeouts
      while @timeouts.first&.disabled?
        @timeouts.shift
      end

      return if @timeouts.empty?

      interval = @timeouts.first.interval

      interval >= 0 ? interval : 0
    end

    def inspect
      @timeouts.inspect
    end

    private

    def call_in(duration, action, *args, fiber: Fiber.current, &block)
      timeout = Timeout.new(duration, fiber, action, *args)

      if @timeouts.empty?
        @timeouts << timeout
      else
        # binary search
        min = 0
        max = @timeouts.size - 1
        while min <= max
          index = (min + max) / 2
          t = @timeouts[index]

          if t > timeout
            if index.zero? || @timeouts[index - 1] <= timeout
              # found it
              break
            else
              # @timeouts[index - 1] > timeout
              max = index - 1
            end
          else
            # t <= timeout
            index += 1
            min = index
          end
        end

        @timeouts.insert(index, timeout)
      end

      begin
        block.call
      ensure
        # Timeout is disabled if the block finishes earlier.
        timeout.disable
      end
    end
  end
end
