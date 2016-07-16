module LetsencryptHeroku
  class Setup
    class SetupError < StandardError ; end

    PRODUCTION = 'https://acme-v01.api.letsencrypt.org/'
    STAGING    = 'https://acme-staging.api.letsencrypt.org/'

    attr_accessor :config

    def initialize(config)
      @config = config
      @config.endpoint ||= PRODUCTION
      @config.domains = config.domains.split
    end

    def perform
      run_task "preflight" do
        # heroku labs:enable http-sni
        # heroku plugins:install heroku-certs

        # check that ssl endpoint is on
        # check heroku is there
        # check that certs are there
      end

      run_task 'register with letsencrypt server' do
        @private_key = OpenSSL::PKey::RSA.new(4096)
        @client = Acme::Client.new(private_key: @private_key, endpoint: config.endpoint)
        @client.register(contact: "mailto:#{config.contact}").agree_terms or fail_task('failed resiger')
      end

      config.domains.each do |domain|
        run_task "authorize #{domain}" do
          @challenge = @client.authorize(domain: domain).http01

          command = "heroku config:set LETSENCRYPT_RESPONSE=#{@challenge.file_content}"
          output = Bundler.with_clean_env { `#{command}` }
          $?.success? or fail_task(output)

          test_response(domain: domain, challenge: @challenge)

          @challenge.request_verification
          sleep(1) while 'pending' == @challenge.verify_status
          @challenge.verify_status == 'valid' or fail_task("failed authorization")
        end
      end

      # if has cert: update cert, else add cert

      run_task "update certificates" do
        csr = Acme::Client::CertificateRequest.new(names: config.domains)
        certificate = @client.new_certificate(csr)
        File.write('privkey.pem', certificate.request.private_key.to_pem)
        File.write('fullchain.pem', certificate.fullchain_to_pem)

        command = "heroku _certs:update fullchain.pem privkey.pem --confirm #{config.herokuapp}"
        output = Bundler.with_clean_env { `#{command}` }
        $?.success? or fail_task(output)

        FileUtils.rm %w(privkey.pem fullchain.pem)
      end
    rescue SetupError => e
      puts Rainbow(e.message).red
    end

    def test_response(domain:, challenge:)
      url = "http://#{domain}/#{challenge.filename}"
      fail_count = 0
      while fail_count < 30
        answer = `curl -sL #{url}`
        if answer != challenge.file_content
          fail_count += 1
          sleep(1)
        else
          return
        end
      end
      fail_task('failed test response')
    end

    def run_task(name)
      @_current_task = name
      print Rainbow("      #{@_current_task}").yellow
      yield
      puts Rainbow("\r    ✔ #{@_current_task}").green
    end

    def fail_task(reason = nil)
      puts Rainbow("\r    ✘ #{@_current_task}").red
      raise SetupError, reason
    end
  end
end
