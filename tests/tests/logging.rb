# Include helper objects and methods.
require_helper "errors"
require_helper "monitoring"

# Test specific helpers.
#
helpers do
  # Missing log entries error.
  #
  class MissingLogMessageError < VirtualMonkey::TestCase::ErrorBase
  end

  # Gets the array of Logging servers in the deployment.
  #
  # @return [Array] an Array of ServerInterfaces of Logging servers
  #
  # @raise [SelectSetError] if no Logging servers found
  #
  def logging_servers
    result = select_set(/Logging/)
    raise SelectSetError, "No Logging servers found." unless result.length > 0
    result
  end

  # Gets the array of Base servers in the deployment.
  #
  # @return [Array] an Array of ServerInterfaces of Base servers
  #
  # @raise [SelectSetError] if no Base servers found
  #
  def base_servers
    result = select_set(/Base/)
    raise SelectSetError, "No Base servers found." unless result.length > 0
    result
  end

  # Sets the server 'logging/remote_server' input to the Logging server IP
  #
  # @param server [ServerInterface] the server to set the input for
  # @param logging_server [ServerInterface] the Logging server
  #
  def set_input_to_logging_server_ip(server, logging_server)
    logging_server_ip = logging_server.private_ip
    logging_server_ip = logging_server.reachable_ip unless logging_server_ip
    server.set_input('logging/remote_server', "text:#{logging_server_ip}")
  end

  # Tests whether the Logging server receives the clients log messages.
  #
  # @param server [ServerInterface] the client server
  # @param logging_server [ServerInterface] the Logging server
  #
  def check_remote_logging(server, logging_server)
    # Generating test string to pass from client to server.
    test_string = "Checking remote logging: #{server.reachable_ip} "
    test_string << rand(32**32).to_s(32)

    # Creates a log message with the test string on the client server.
    probe(server, "logger \"#{test_string}\"") do |result, status|
      unless status == 0
        raise FailedProbeCommandError, "Failed to create log message: #{result}"
      end
      true
    end

    # Sleeping for 5s: this time is needed for the log message to leave the
    # client server, be sent to the logging server, get processed and added to
    # the /var/log/messages|syslog file of the server.
    sleep(5)

    # Gets logging server OS.
    operating_system = ""
    probe(logging_server, "lsb_release -a | grep -ir description") do
    |result, status|
      unless status == 0
        raise FailedProbeCommandError, "Failed to get server OS: #{result}"
      end
      operating_system = result.to_s
      true
    end

    # Sets server log file path depending on the OS.
    log_file_path =
      case operating_system
      when /ubuntu.*12/i
        "/var/log/syslog"
      else
        "/var/log/messages"
      end

    # Checks whether the log with the test string is on the Logging server.
    probe(logging_server, "grep \"#{test_string}\" #{log_file_path}") do
    |result, status|
      if result.empty?
        raise MissingLogMessageError, "Log meaasge\"#{test_string}\" not" +
          " found on the Logging server"
      end
      raise FailedProbeCommandError, "Probe error: #{result}" unless status == 0
      true
    end
  end

  # Launches a Logging server listening on a specified protocol, waits until
  # it is operational and checks its monitoring, then sets up the inputs for the
  # client server, launches the client and checks remote logging.
  # The test assumes there is one Logging server and one client Base server.
  #
  # @param protocol [String] the protocol used to pass log messages
  #
  def run_log_test(protocol)
    # Stops the servers in the deployment for the test.
    stop_all

    # Defines the Logging server and client Base server used for the test.
    logging_server = logging_servers.first
    base_server = base_servers.first

    # Sets up the Logging server, checks its monitoring.
    logging_server.set_input('logging/protocol', "text:#{protocol}")
    launch_set(logging_server)
    wait_for_set(logging_server, "operational")
    check_monitoring(logging_server)

    # Sets up the client server.
    set_input_to_logging_server_ip(base_server, logging_server)
    base_server.set_input('logging/protocol', "text:#{protocol}")
    launch_set(base_server)
    wait_for_set(base_server, "operational")

    # Tests whether the Logging server receives the clients log messages.
    check_remote_logging(base_server, logging_server)
  end
end


# The 'smoke_test' test_case for the Logging with rsyslog ServerTemplate ensures
# that the basic UDP logging functionality is working correctly.
#
test_case "smoke_test" do
  run_log_test("udp")
end

# The 'relp' test_case for the Logging with rsyslog ServerTemplate ensures that
# the remote logging functionality over the RELP protocol is working correctly.
#
test_case "relp" do
  run_log_test("relp")
end

# The 'relp-secured' test_case for the Logging with rsyslog ServerTemplate
# ensures that the remote logging functionality over the RELP protocol with SSL
# encryption is working correctly.
#
test_case "relp-secured" do
  run_log_test("relp-secured")
end
