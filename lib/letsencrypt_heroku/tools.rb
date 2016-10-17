module LetsencryptHeroku
  module Tools
    def banner(msg, values = nil)
      puts "\n #{Rainbow(msg).blue} #{values.to_s}\n\n"
    end

    def output(name)
      log name
      @_spinner = build_spinner(name)
      @_spinner.start
      yield
      @_spinner.success
    rescue LetsencryptHeroku::TaskError
      exit
    end

    def log(message, level: :info)
      message.to_s.empty? and return
      level == :info ? logger.info(message) : logger.error(message)
    end

    def error(reason = nil)
      log reason, level: :error
      @_spinner && @_spinner.error("(#{reason.strip})")
      raise LetsencryptHeroku::TaskError, reason
    end

    def execute(command)
      log command
      Bundler.with_clean_env do
        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          out, err = stdout.read, stderr.read
          log out
          log err
          wait_thr.value.success? or error(err.force_encoding('utf-8').sub(' ▸    ', 'heroku: '))
        end
      end
    end

    private

    def logger
      @logger ||= Logger.new(File.open('log/letsencrypt_heroku.log', File::WRONLY | File::APPEND | File::CREAT))
    end

    def build_spinner(name)
      TTY::Spinner.new(" :spinner #{name}",
        format:       :dots,
        interval:     20,
        frames:       [ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" ].map { |s| Rainbow(s).yellow.bright },
        success_mark: Rainbow('✔').green,
        error_mark:   Rainbow('✘').red
      )
    end
  end
end
