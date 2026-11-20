class QueryJob < ApplicationJob
  # What happened in the job, for the tests: [context, error].
  RESULTS = Queue.new

  def perform(token)
    error = nil

    begin
      ActiveRecord::Base.connection.exec_query(
        "SELECT name FROM users WHERE token = '#{token}'"
      )
    rescue => err
      error = err
    end

    RESULTS << [Aikido::Zen.current_context, error]
  end
end
